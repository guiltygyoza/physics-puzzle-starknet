%lang starknet
%builtins pedersen range_check

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import (signed_div_rem, unsigned_div_rem, sign, assert_nn, abs_value, assert_not_zero)
from starkware.cairo.common.math_cmp import (is_nn, is_le, is_not_zero)
from starkware.cairo.common.alloc import alloc

struct BallState:
    member x : felt
    member y : felt
    member vx : felt
    member vy : felt
    member ax : felt
    member ay : felt
end

struct SystemState:
    member ball_score1 : BallState
    member ball_score2 : BallState
    member ball_score3 : BallState
    member ball_forbid : BallState
    member ball_player : BallState
end

const RANGE_CHECK_BOUND = 2 ** 64
const SCALE_FP = 100*100
const SCALE_FP_SQRT = 100
const BALL_R = 20 * SCALE_FP
const R2SQ = 1600 * SCALE_FP  # (R + R)**2
const Y_MAX = (400-20) * SCALE_FP
const Y_MIN = 20 * SCALE_FP
const X_MAX = (400-20) * SCALE_FP
const X_MIN = 20 * SCALE_FP

#################################

func sqrt_fp {range_check_ptr}(x : felt) -> (y : felt):
    let (x_) = sqrt(x)
    let y = x_ * SCALE_FP_SQRT # compensate for the square root operation
    return (y)
end

func sqrt{range_check_ptr}(x : felt) -> (y : felt):
    alloc_locals

    const MAX_ITER = 200

    assert_nn(x)

    if x == 0:
        return (y=0)
    else:
        # start at x with MAX_ITER iterations (gas on StarkNet is cheap)
        let (y) = _sqrt_loop(x, x, MAX_ITER)

        return (y=y)
    end
end

# Compute square root of `x` using Newton/babylonian method.
func _sqrt_loop{range_check_ptr}(x : felt, xn : felt, iter : felt) -> (y : felt):
    alloc_locals

    if iter == 0:
        return (y=xn)
    end

    # best guess is arithmetic mean of `xn` and `x/xn`.
    let (local x_over_xn, _) = unsigned_div_rem(x, xn)
    let (local xn_, _) = unsigned_div_rem(xn + x_over_xn, 2)

    let (should_continue) = is_le(xn_, xn)

    if should_continue != 0:
        return _sqrt_loop(x, xn_, iter - 1)
    else:
        # return previous iteration since we want a lower bounding result.
        return (y=xn)
    end
end

### Utility functions for fixed-point arithmetic
func mul_fp {range_check_ptr} (
        a : felt,
        b : felt
    ) -> (
        c : felt
    ):
    # signed_div_rem by SCALE_FP after multiplication
    tempvar product = a * b
    let (c, _) = signed_div_rem(product, SCALE_FP, RANGE_CHECK_BOUND)
    return (c)
end

func div_fp {range_check_ptr} (
        a : felt,
        b : felt
    ) -> (
        c : felt
    ):
    # multiply by SCALE_FP before signed_div_rem
    tempvar a_scaled = a * SCALE_FP
    let (c, _) = signed_div_rem(a_scaled, b, RANGE_CHECK_BOUND)
    return (c)
end

func distance {range_check_ptr} (
        x1 : felt,
        y1 : felt,
        x2 : felt,
        y2 : felt
    ) -> (
        distance : felt
    ):
    alloc_locals

    # let (local distance_x_2) = mul_fp(x2-x1, x2-x1)
    # let (distance_y_2) = mul_fp(y2-y1, y2-y1)
    # tempvar distance_2 = distance_x_2 + distance_y_2
    # let (distance) = sqrt_fp (distance_2)

    # the following code is equivalent to above
    tempvar distance_2 = (x2-x1) * (x2-x1) + (y2-y1) * (y2-y1)
    let (distance) = sqrt (distance_2)

    return (distance)
end

#################################

@external
func euler_forward {
        syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr
    } (
        state : SystemState,
        first : felt
    ) -> (
        state_nxt : SystemState,
        broke_the_law : felt,
        scored_s1 : felt,
        scored_s2 : felt,
        scored_s3 : felt
    ):
    alloc_locals

    const dt = 600 # 0.06 * 10000 = 600

    ##########
    # Unpack #
    ##########
    local s1 : BallState = state.ball_score1
    local s2 : BallState = state.ball_score2
    local s3 : BallState = state.ball_score3
    local fb : BallState = state.ball_forbid
    local pl : BallState = state.ball_player

    ##############
    # Euler step #
    ##############
    let (local s1_cand : BallState, local s1_has_collided_with_boundary) = euler_step_single_circle (dt, s1)
    let (local s2_cand : BallState, local s2_has_collided_with_boundary) = euler_step_single_circle (dt, s2)
    let (local s3_cand : BallState, local s3_has_collided_with_boundary) = euler_step_single_circle (dt, s3)
    let (local fb_cand : BallState, local fb_has_collided_with_boundary) = euler_step_single_circle (dt, fb)
    let (local pl_cand : BallState, local pl_has_collided_with_boundary) = euler_step_single_circle (dt, pl)

    ####################
    # Handle collision #
    ####################
    # s1 <-> s2 <-> s3
    let (local s1_nxt_ : BallState, local s2_nxt_ : BallState, local s1_s2_has_collided) = collision_pair_circles (s1, s2, s1_cand, s2_cand)
    let (local s2_nxt__ : BallState, local s3_nxt_ : BallState, local s2_s3_has_collided) = collision_pair_circles (s2, s3, s2_nxt_, s3_cand)
    let (local s1_nxt__ : BallState, local s3_nxt__ : BallState, local s1_s3_has_collided) = collision_pair_circles (s1, s3, s1_nxt_, s3_nxt_)

    # s1, fb
    let (local s1_nxt___ : BallState, local fb_nxt_ : BallState, local s1_fb_has_collided) = collision_pair_circles (s1, fb, s1_nxt__, fb_cand)

    # s1, pl
    let (local s1_nxt____ : BallState, local pl_nxt_ : BallState, local s1_pl_has_collided) = collision_pair_circles (s1, pl, s1_nxt___, pl_cand)

    # s2, fb
    let (local s2_nxt___ : BallState, local fb_nxt__ : BallState, local s2_fb_has_collided) = collision_pair_circles (s2, fb, s2_nxt__, fb_nxt_)

    # s2, pl
    let (local s2_nxt____ : BallState, local pl_nxt__ : BallState, local s2_pl_has_collided) = collision_pair_circles (s2, pl, s2_nxt___, pl_nxt_)

    # s3, fb
    let (local s3_nxt___ : BallState, local fb_nxt___ : BallState, local s3_fb_has_collided) = collision_pair_circles (s3, fb, s3_nxt__, fb_nxt__)

    # s3, pl
    let (local s3_nxt____ : BallState, local pl_nxt___ : BallState, local s3_pl_has_collided) = collision_pair_circles (s3, pl, s3_nxt___, pl_nxt__)

    # fb, pl
    let (local fb_nxt____ : BallState, local pl_nxt____ : BallState, local fb_pl_has_collided) = collision_pair_circles (fb, pl, fb_nxt___, pl_nxt___)

    ###################
    # Handle friction #
    ###################
    # s1
    tempvar sum_s1_bools = first + s1_has_collided_with_boundary + s1_s2_has_collided + s1_s3_has_collided + s1_fb_has_collided + s1_pl_has_collided
    let (s1_should_recalc_friction) = is_not_zero (sum_s1_bools)
    #let s1_should_recalc_friction = 1
    let (
        local s1_final : BallState
    ) = friction_single_circle (dt=dt, c=s1_nxt____, should_recalc=s1_should_recalc_friction)

    # s2
    tempvar sum_s2_bools = first + s2_has_collided_with_boundary + s1_s2_has_collided + s2_s3_has_collided + s2_fb_has_collided + s2_pl_has_collided
    let (s2_should_recalc_friction) = is_not_zero (sum_s2_bools)
    #let s2_should_recalc_friction = 1
    let (
        local s2_final : BallState
    ) = friction_single_circle (dt=dt, c=s2_nxt____, should_recalc=s2_should_recalc_friction)

    # s3
    tempvar sum_s3_bools = first + s3_has_collided_with_boundary + s1_s3_has_collided + s2_s3_has_collided + s3_fb_has_collided + s3_pl_has_collided
    let (s3_should_recalc_friction) = is_not_zero (sum_s3_bools)
    #let s3_should_recalc_friction = 1
    let (
        local s3_final : BallState
    ) = friction_single_circle (dt=dt, c=s3_nxt____, should_recalc=s3_should_recalc_friction)

    # fb
    tempvar sum_fb_bools = first + fb_has_collided_with_boundary + s1_fb_has_collided + s2_fb_has_collided + s3_fb_has_collided + fb_pl_has_collided
    let (fb_should_recalc_friction) = is_not_zero (sum_fb_bools)
    #let fb_should_recalc_friction = 1
    let (
        local fb_final : BallState
    ) = friction_single_circle (dt=dt, c=fb_nxt____, should_recalc=fb_should_recalc_friction)

    # pl
    tempvar sum_pl_bools = first + pl_has_collided_with_boundary + s1_pl_has_collided + s2_pl_has_collided + s3_pl_has_collided + fb_pl_has_collided
    let (pl_should_recalc_friction) = is_not_zero (sum_pl_bools)
    #let pl_should_recalc_friction = 1
    let (
        pl_final : BallState
    ) = friction_single_circle (dt=dt, c=pl_nxt____, should_recalc=pl_should_recalc_friction)

    ########
    # Pack #
    ########
    local state_nxt : SystemState = SystemState (
        s1_final, s2_final, s3_final, fb_final, pl_final)

    ## return system and collision bools. bools the game cares about:
    ## 1. s1_fb, s2_fb, s2_fb, pl_fb => leads to score == 0
    ## 2. s1_pl, s2_pl, s3_pl => leads to score increment by various amounts
    tempvar sum_illegal_bools = s1_fb_has_collided + s2_fb_has_collided + s3_fb_has_collided + fb_pl_has_collided
    let (broke_the_law) = is_not_zero (sum_illegal_bools)
    let scored_s1 = s1_pl_has_collided
    let scored_s2 = s2_pl_has_collided
    let scored_s3 = s3_pl_has_collided

    return (state_nxt, broke_the_law, scored_s1, scored_s2, scored_s3)
end

#################################

func euler_step_single_circle {range_check_ptr} (
        dt : felt,
        c : BallState
    ) -> (
        c_nxt : BallState,
        has_collided_with_boundary : felt
    ):
    alloc_locals

    ## Calculate candidate nxt position and velocity
    let (x_delta)    = mul_fp (c.vx, dt)
    local x_nxt_cand = c.x + x_delta
    let (y_delta)    = mul_fp (c.vy, dt)
    local y_nxt_cand = c.y + y_delta

    ## check c <-> x boundary and y boundary and handle bounce
    tempvar mass_to_xmax = x_nxt_cand - X_MAX
    let (local b_xmax) = is_nn (mass_to_xmax)
    tempvar xmin_to_mass = X_MIN - x_nxt_cand
    let (local b_xmin) = is_nn (xmin_to_mass)
    local x_nxt  = (1-b_xmax-b_xmin) * x_nxt_cand + b_xmax * X_MAX + b_xmin * X_MIN
    local vx_nxt = (1-b_xmax-b_xmin) * c.vx + b_xmax * (-c.vx) + b_xmin * (-c.vx)

    tempvar ymin_to_mass = Y_MIN - y_nxt_cand
    let (local b_ymin) = is_nn (ymin_to_mass)
    tempvar mass_to_ymax = y_nxt_cand - Y_MAX
    let (local b_ymax) = is_nn (mass_to_ymax)
    local y_nxt  = (1-b_ymin-b_ymax) * y_nxt_cand + b_ymin * Y_MIN + b_ymax * Y_MAX
    local vy_nxt = (1-b_ymin-b_ymax) * c.vy + b_ymin * (-c.vy) + b_ymax * (-c.vy)

    ## Summarizing the bools
    tempvar bool_sum = b_xmax + b_xmin + b_ymin + b_ymax
    let (has_collided_with_boundary) = is_not_zero (bool_sum)

    ## Pack to Point
    #let (c_nxt : BallState*) = alloc()
    # assert c_nxt[0] = BallState (
    #     x = x_nxt, y = y_nxt, vx = vx_nxt, vy = vy_nxt, ax = c.ax, ay = c.ay
    # )
    let c_nxt = BallState (
        x = x_nxt, y = y_nxt, vx = vx_nxt, vy = vy_nxt, ax = c.ax, ay = c.ay
    )

    return (c_nxt, has_collided_with_boundary)
end

#################################

func collision_pair_circles {range_check_ptr} (
        c1 : BallState,
        c2 : BallState,
        c1_cand : BallState,
        c2_cand : BallState
    ) -> (
        c1_nxt : BallState,
        c2_nxt : BallState,
        has_collided : felt
    ):
    alloc_locals

    ## Algorithm for each circle:
    ##   if line-intersect with another cirlce's line => snap to impact position and exchange vx & vy
    ##   using cheap solution now: run circle-test at candidate position. Assumption: dt is small enough relatively to radius such that
    ##                             it is impossible for collision to happen without failing the circle-test at candidate positions
    ##   bettter solution: also check for *tunneling* i.e. collision that would have occurred inbetween frames, and handle it
    ##                     skipping this for now to focus on improving performance + vectorization

    ## Check whether candidate c1 collides with candidate c2
    tempvar x1mx2 = c1_cand.x - c2_cand.x
    let (local x1mx2_sq) = mul_fp (x1mx2, x1mx2)
    tempvar y1my2 = c1_cand.y - c2_cand.y
    let (y1my2_sq) = mul_fp (y1my2, y1my2)
    tempvar d12_sq = x1mx2_sq + y1my2_sq
    let (local bool_c1_c2_cand_collided) = is_le (d12_sq, R2SQ)

    local range_check_ptr = range_check_ptr
    local x1_nxt
    local y1_nxt
    local x2_nxt
    local y2_nxt
    local vx1_nxt
    local vy1_nxt
    local vx2_nxt
    local vy2_nxt

    if bool_c1_c2_cand_collided == 0:
        # not colliding => finalize with candidate
        assert x1_nxt  = c1_cand.x
        assert y1_nxt  = c1_cand.y
        assert x2_nxt  = c2_cand.x
        assert y2_nxt  = c2_cand.y
        assert vx1_nxt = c1_cand.vx
        assert vy1_nxt = c1_cand.vy
        assert vx2_nxt = c2_cand.vx
        assert vy2_nxt = c2_cand.vy

        tempvar range_check_ptr = range_check_ptr
    else:
        ## Handle c1 <-> c2 collision: back each off to the calculated impact point* TODO add note on how to calculate
        let (local d_cand) = distance(c1_cand.x, c1_cand.y, c2_cand.x, c2_cand.y)
        local nom = BALL_R + BALL_R - d_cand
        let (d) = distance(c1.x, c1.y, c2.x, c2.y)
        local denom = d - d_cand

        let (nom_x1) = mul_fp (nom, c1_cand.x - c1.x)
        let (x1_delta) = div_fp(nom_x1,denom)
        assert x1_nxt = c1_cand.x - x1_delta

        let (nom_y1) = mul_fp (nom, c1_cand.y - c1.y)
        let (y1_delta) = div_fp(nom_y1,denom)
        assert y1_nxt = c1_cand.y - y1_delta

        let (nom_x2) = mul_fp (nom, c2_cand.x - c2.x)
        let (x2_delta) = div_fp(nom_x2,denom)
        assert x2_nxt = c2_cand.x - x2_delta

        let (nom_y2) = mul_fp (nom, c2_cand.y - c2.y)
        let (y2_delta) = div_fp(nom_y2,denom)
        assert y2_nxt = c2_cand.y - y2_delta

        let (local alpha_nom1) = mul_fp ( c2.vx-c1.vx, x2_nxt-x1_nxt )
        let (local alpha_nom2) = mul_fp ( c2.vy-c1.vy, y2_nxt-y1_nxt )
        let (local alpha_denom1) = mul_fp ( x2_nxt-x1_nxt, x2_nxt-x1_nxt )
        let (alpha_denom2) = mul_fp ( y2_nxt-y1_nxt, y2_nxt-y1_nxt )
        let (local alpha) = div_fp ( alpha_nom1+alpha_nom2, alpha_denom1+alpha_denom2 )

        let (vx1_delta) = mul_fp ( alpha, x1_nxt-x2_nxt )
        assert vx1_nxt = c1.vx - vx1_delta

        let (vy1_delta) = mul_fp ( alpha, y1_nxt-y2_nxt )
        assert vy1_nxt = c1.vy - vy1_delta

        let (vx2_delta) = mul_fp ( alpha, x2_nxt-x1_nxt )
        assert vx2_nxt = c2.vx - vx2_delta

        let (vy2_delta) = mul_fp ( alpha, y2_nxt-y1_nxt )
        assert vy2_nxt = c2.vy - vy2_delta

        #assert vx1_nxt = c2.vx
        #assert vy1_nxt = c2.vy
        #assert vx2_nxt = c1.vx
        #assert vy2_nxt = c1.vy

        tempvar range_check_ptr = range_check_ptr
    end

    ## Pack to Point
    # let (c1_nxt : BallState*) = alloc()
    # assert c1_nxt[0] = BallState (
    #     x = x1_nxt, y = y1_nxt, vx = vx1_nxt, vy = vy1_nxt, ax = c1.ax, ay = c1.ay
    # )
    let c1_nxt = BallState (
        x = x1_nxt, y = y1_nxt, vx = vx1_nxt, vy = vy1_nxt, ax = c1.ax, ay = c1.ay
    )

    # let (c2_nxt : BallState*) = alloc()
    # assert c2_nxt[0] = BallState (
    #     x = x2_nxt, y = y2_nxt, vx = vx2_nxt, vy = vy2_nxt, ax = c2.ax, ay = c2.ay
    # )
    let c2_nxt = BallState (
        x = x2_nxt, y = y2_nxt, vx = vx2_nxt, vy = vy2_nxt, ax = c2.ax, ay = c2.ay
    )

    tempvar has_collided = bool_c1_c2_cand_collided

    return (c1_nxt, c2_nxt, has_collided)
end

#################################

func friction_single_circle {range_check_ptr} (
        dt : felt,
        c : BallState,
        should_recalc : felt
    ) -> (
        c_nxt : BallState
    ):
    alloc_locals

    const A_FRICTION = 30 * SCALE_FP # constant magnitude deacceleration determined by mu and g

    local vx_nxt_friction
    local vy_nxt_friction
    local ax_nxt
    local ay_nxt

    if should_recalc == 1:
        # recalc: calculate v, then if v!=0 calculate ax and ay
        # let (local vx_sq) = mul_fp (c.vx, c.vx)
        # let (vy_sq) = mul_fp (c.vy, c.vy)
        # tempvar v_sq = vx_sq + vy_sq
        # let (local v) = sqrt_fp (v_sq)

        ## the following code is equivalent to above
        tempvar v_2 = c.vx * c.vx + c.vy * c.vy
        let (local v) = sqrt (v_2)

        #local ax_recalc
        #local ay_recalc
        local ax_dt
        local ay_dt
        if v == 0:
            assert ax_dt = 0
            assert ay_dt = 0
            assert ax_nxt = 0
            assert ay_nxt = 0

            tempvar range_check_ptr = range_check_ptr
        else:
            let (a_mul_vx) = mul_fp (A_FRICTION, c.vx)
            let (ax) = div_fp (a_mul_vx, v)
            assert ax_nxt = ax # recalc
            let (axdt) = mul_fp (ax, dt)
            assert ax_dt = axdt # for friction application

            let (a_mul_vy) = mul_fp (A_FRICTION, c.vy)
            let (ay) = div_fp (a_mul_vy, v)
            assert ay_nxt = ay # recalc
            let (aydt) = mul_fp (ay, dt)
            assert ay_dt = aydt # for friction application
            tempvar range_check_ptr = range_check_ptr
        end

        # apply with clipping to 0
        let (local vx_abs) = abs_value (c.vx)
        let (ax_dt_abs) = abs_value (ax_dt)
        let (local bool_x_stopped) = is_le (vx_abs, ax_dt_abs)
        let (local vy_abs) = abs_value (c.vy)
        let (ay_dt_abs) = abs_value (ay_dt)
        let (local bool_y_stopped) = is_le (vy_abs, ay_dt_abs)

        if bool_x_stopped == 1:
            assert vx_nxt_friction = 0
            # TODO: also zero out ax!
            tempvar range_check_ptr = range_check_ptr
        else:
            assert vx_nxt_friction = c.vx - ax_dt
            tempvar range_check_ptr = range_check_ptr
        end

        if bool_y_stopped == 1:
            assert vy_nxt_friction = 0
            # TODO: also zero out ay!
            tempvar range_check_ptr = range_check_ptr
        else:
            assert vy_nxt_friction = c.vy - ay_dt
            tempvar range_check_ptr = range_check_ptr
        end

        tempvar range_check_ptr = range_check_ptr
    else:
        ## apply with clipping to 0
        let (local ax_dt) = mul_fp (c.ax, dt)
        let (local vx_abs) = abs_value (c.vx)
        let (ax_dt_abs) = abs_value(ax_dt)
        let (bool_x_stopped) = is_le (vx_abs, ax_dt_abs)
        if bool_x_stopped == 1:
            assert vx_nxt_friction = 0
            assert ax_nxt = 0

            tempvar range_check_ptr = range_check_ptr
        else:
            assert vx_nxt_friction = c.vx - ax_dt
            assert ax_nxt = c.ax

            tempvar range_check_ptr = range_check_ptr
        end

        let (local ay_dt) = mul_fp (c.ay, dt)
        let (local vy_abs) = abs_value (c.vy)
        let (ay_dt_abs) = abs_value (ay_dt)
        let (bool_y_stopped) = is_le (vy_abs, ay_dt_abs)
        if bool_y_stopped == 1:
            assert vy_nxt_friction = 0
            assert ay_nxt = 0

            tempvar range_check_ptr = range_check_ptr
        else:
            assert vy_nxt_friction = c.vy - ay_dt
            assert ay_nxt = c.ay

            tempvar range_check_ptr = range_check_ptr
        end
    end

    # let (c_nxt : BallState*) = alloc()
    # assert c_nxt[0] = BallState (
    #     x = c.x, y = c.y, vx = vx_nxt_friction, vy = vy_nxt_friction, ax = ax_nxt, ay = ay_nxt
    # )
    let c_nxt = BallState (
        x = c.x, y = c.y, vx = vx_nxt_friction, vy = vy_nxt_friction, ax = ax_nxt, ay = ay_nxt
    )

    return (c_nxt)
end
