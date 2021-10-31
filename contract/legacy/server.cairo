%lang starknet
%builtins range_check

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math_cmp import (is_not_zero)
from starkware.cairo.common.math import (abs_value, assert_not_zero, assert_le)

## Constants for scoring
## TODO: can we define these elsewhere?
const SCORE_S1 = 10
const SCORE_S2 = 15
const SCORE_S3 = 20

const SCALE_FP = 100*100

func is_zero {range_check_ptr} (value) -> (res):
    # invert the result of is_not_zero()
    let (temp) = is_not_zero(value)
    if temp == 0:
        return (res=1)
    end

    return (res=0)
end

## TODO this struct has been defined in manager.cairo. Can I avoid redefining it here?
struct PuzzleState:
    member ball_score1_x : felt
    member ball_score1_y : felt
    member ball_score2_x : felt
    member ball_score2_y : felt
    member ball_score3_x : felt
    member ball_score3_y : felt
    member ball_forbid_x : felt
    member ball_forbid_y : felt
    member ball_player_x : felt
    member ball_player_y : felt
end

struct BallState:
    member x : felt
    member y : felt
    member vx : felt
    member vy : felt
    member ax : felt
    member ay : felt
end

struct SystemState:
    member ball_score1 : BallState*
    member ball_score2 : BallState*
    member ball_score3 : BallState*
    member ball_forbid : BallState*
    member ball_player : BallState*
end

## Contract interfaces
@contract_interface
namespace IContractChef:
    # struct version
    # func euler_forward (
    #         state : SystemState
    #     ) -> (
    #         state_nxt : SystemState,
    #         TODO collision bools
    #     ):
    # end

    # non struct version
    func euler_forward (
            s1_x, s1_y, s1_vx, s1_vy, s1_ax, s1_ay,
            s2_x, s2_y, s2_vx, s2_vy, s2_ax, s2_ay,
            s3_x, s3_y, s3_vx, s3_vy, s3_ax, s3_ay,
            fb_x, fb_y, fb_vx, fb_vy, fb_ax, fb_ay,
            pl_x, pl_y, pl_vx, pl_vy, pl_ax, pl_ay
        ) -> (
            s1_x_nxt, s1_y_nxt, s1_vx_nxt, s1_vy_nxt, s1_ax_nxt, s1_ay_nxt,
            s2_x_nxt, s2_y_nxt, s2_vx_nxt, s2_vy_nxt, s2_ax_nxt, s2_ay_nxt,
            s3_x_nxt, s3_y_nxt, s3_vx_nxt, s3_vy_nxt, s3_ax_nxt, s3_ay_nxt,
            fb_x_nxt, fb_y_nxt, fb_vx_nxt, fb_vy_nxt, fb_ax_nxt, fb_ay_nxt,
            pl_x_nxt, pl_y_nxt, pl_vx_nxt, pl_vy_nxt, pl_ax_nxt, pl_ay_nxt,
            broke_the_law : felt,
            scored_s1 : felt,
            scored_s2 : felt,
            scored_s3 : felt
        ):
    end
end

#################################

@external
func run_simulation {
        syscall_ptr : felt*,
        range_check_ptr
    } (
        chef_address : felt,
        s1_x : felt, s1_y : felt, s2_x : felt, s2_y : felt, s3_x : felt, s3_y : felt,
        fb_x : felt, fb_y : felt, pl_x : felt, pl_y : felt,
        ball_player_vx : felt, ball_player_vy : felt
    ) -> (
        s1_x_final : felt, s1_y_final : felt, s2_x_final : felt, s2_y_final : felt,
        s3_x_final : felt, s3_y_final : felt, fb_x_final : felt, fb_y_final : felt,
        pl_x_final : felt, pl_y_final : felt,
        score : felt
    ):
    alloc_locals

    let (dbg_isz) = is_zero(s1_x - 300 * SCALE_FP)
    assert_not_zero (dbg_isz)

    let (
        s1_x_final, s1_y_final, _, _, _, _,
        s2_x_final, s2_y_final, _, _, _, _,
        s3_x_final, s3_y_final, _, _, _, _,
        fb_x_final, fb_y_final, _, _, _, _,
        pl_x_final, pl_y_final, _, _, _, _,
        sum_broke_the_law, sum_scored_s1, sum_scored_s2, sum_scored_s3
    ) = _recurse_euler_forward (
        chef_address,
        s1_x, s1_y, 0, 0, 0, 0,
        s2_x, s2_y, 0, 0, 0, 0,
        s3_x, s3_y, 0, 0, 0, 0,
        fb_x, fb_y, 0, 0, 0, 0,
        pl_x, pl_y, ball_player_vx, ball_player_vy, 0, 0
    )


    let (safe) = is_zero (sum_broke_the_law)
    tempvar tentative_score = sum_scored_s1 * SCORE_S1 + sum_scored_s2 * SCORE_S2 + sum_scored_s3 * SCORE_S3
    local score = tentative_score * safe

    let (dbg_isz) = is_zero(s1_x_final - 300 * SCALE_FP)
    assert_not_zero (dbg_isz)

    return (
        s1_x_final, s1_y_final,
        s2_x_final, s2_y_final,
        s3_x_final, s3_y_final,
        fb_x_final, fb_y_final,
        pl_x_final, pl_y_final,
        score
    )
end

######

func _recurse_euler_forward {
        syscall_ptr : felt*,
        range_check_ptr
    }(
        chef_address : felt,
        s1_x : felt, s1_y : felt, s1_vx : felt, s1_vy : felt, s1_ax : felt, s1_ay : felt,
        s2_x : felt, s2_y : felt, s2_vx : felt, s2_vy : felt, s2_ax : felt, s2_ay : felt,
        s3_x : felt, s3_y : felt, s3_vx : felt, s3_vy : felt, s3_ax : felt, s3_ay : felt,
        fb_x : felt, fb_y : felt, fb_vx : felt, fb_vy : felt, fb_ax : felt, fb_ay : felt,
        pl_x : felt, pl_y : felt, pl_vx : felt, pl_vy : felt, pl_ax : felt, pl_ay : felt
    ) -> (
        s1_x_final : felt, s1_y_final : felt, s1_vx_final : felt, s1_vy_final : felt, s1_ax_final : felt, s1_ay_final : felt,
        s2_x_final : felt, s2_y_final : felt, s2_vx_final : felt, s2_vy_final : felt, s2_ax_final : felt, s2_ay_final : felt,
        s3_x_final : felt, s3_y_final : felt, s3_vx_final : felt, s3_vy_final : felt, s3_ax_final : felt, s3_ay_final : felt,
        fb_x_final : felt, fb_y_final : felt, fb_vx_final : felt, fb_vy_final : felt, fb_ax_final : felt, fb_ay_final : felt,
        pl_x_final : felt, pl_y_final : felt, pl_vx_final : felt, pl_vy_final : felt, pl_ax_final : felt, pl_ay_final : felt,
        sum_broke_the_law : felt, sum_scored_s1 : felt, sum_scored_s2 : felt, sum_scored_s3 : felt
    ):
    alloc_locals

    # 1. calculate forward
    let (
        local s1_x_nxt, local s1_y_nxt, local s1_vx_nxt, local s1_vy_nxt, local s1_ax_nxt, local s1_ay_nxt,
        local s2_x_nxt, local s2_y_nxt, local s2_vx_nxt, local s2_vy_nxt, local s2_ax_nxt, local s2_ay_nxt,
        local s3_x_nxt, local s3_y_nxt, local s3_vx_nxt, local s3_vy_nxt, local s3_ax_nxt, local s3_ay_nxt,
        local fb_x_nxt, local fb_y_nxt, local fb_vx_nxt, local fb_vy_nxt, local fb_ax_nxt, local fb_ay_nxt,
        local pl_x_nxt, local pl_y_nxt, local pl_vx_nxt, local pl_vy_nxt, local pl_ax_nxt, local pl_ay_nxt,
        local broke_the_law, local scored_s1, local scored_s2, local scored_s3
    ) = IContractChef.euler_forward (
        chef_address,
        s1_x, s1_y, s1_vx, s1_vy, s1_ax, s1_ay,
        s2_x, s2_y, s2_vx, s2_vy, s2_ax, s2_ay,
        s3_x, s3_y, s3_vx, s3_vy, s3_ax, s3_ay,
        fb_x, fb_y, fb_vx, fb_vy, fb_ax, fb_ay,
        pl_x, pl_y, pl_vx, pl_vy, pl_ax, pl_ay
    )

    # debug
    assert_le (pl_vy_nxt, pl_vy)

    # 2. return if reached final state
    let (local s1_vx_nxt_abs) = abs_value (s1_vx_nxt)
    let (local s1_vy_nxt_abs) = abs_value (s1_vy_nxt)
    let (local s2_vx_nxt_abs) = abs_value (s2_vx_nxt)
    let (local s2_vy_nxt_abs) = abs_value (s2_vy_nxt)
    let (local s3_vx_nxt_abs) = abs_value (s3_vx_nxt)
    let (local s3_vy_nxt_abs) = abs_value (s3_vy_nxt)
    let (local fb_vx_nxt_abs) = abs_value (fb_vx_nxt)
    let (local fb_vy_nxt_abs) = abs_value (fb_vy_nxt)
    let (local pl_vx_nxt_abs) = abs_value (pl_vx_nxt)
    let (local pl_vy_nxt_abs) = abs_value (pl_vy_nxt)
    let v_abs_sum = s1_vx_nxt_abs + s1_vy_nxt_abs + s2_vx_nxt_abs + s2_vy_nxt_abs + s3_vx_nxt_abs + s3_vy_nxt_abs + fb_vx_nxt_abs + fb_vy_nxt_abs + pl_vx_nxt_abs + pl_vy_nxt_abs

    # debug
    #let (v_abs_sum_is_zero) = is_zero (v_abs_sum)
    #assert_not_zero (v_abs_sum_is_zero)

    if v_abs_sum == 0:
        return(
            s1_x_nxt, s1_y_nxt, s1_vx_nxt, s1_vy_nxt, s1_ax_nxt, s1_ay_nxt,
            s2_x_nxt, s2_y_nxt, s2_vx_nxt, s2_vy_nxt, s2_ax_nxt, s2_ay_nxt,
            s3_x_nxt, s3_y_nxt, s3_vx_nxt, s3_vy_nxt, s3_ax_nxt, s3_ay_nxt,
            fb_x_nxt, fb_y_nxt, fb_vx_nxt, fb_vy_nxt, fb_ax_nxt, fb_ay_nxt,
            pl_x_nxt, pl_y_nxt, pl_vx_nxt, pl_vy_nxt, pl_ax_nxt, pl_ay_nxt,
            broke_the_law, scored_s1, scored_s2, scored_s3
        )
    end

    # 3. otherwise, recurse
    let (
        s1_x_final, s1_y_final, s1_vx_final, s1_vy_final, s1_ax_final, s1_ay_final,
        s2_x_final, s2_y_final, s2_vx_final, s2_vy_final, s2_ax_final, s2_ay_final,
        s3_x_final, s3_y_final, s3_vx_final, s3_vy_final, s3_ax_final, s3_ay_final,
        fb_x_final, fb_y_final, fb_vx_final, fb_vy_final, fb_ax_final, fb_ay_final,
        pl_x_final, pl_y_final, pl_vx_final, pl_vy_final, pl_ax_final, pl_ay_final,
        rest_of_sum_broke_the_law, rest_of_sum_scored_s1, rest_of_sum_scored_s2, rest_of_sum_scored_s3
    ) = _recurse_euler_forward (
        chef_address,
        s1_x_nxt, s1_y_nxt, s1_vx_nxt, s1_vy_nxt, s1_ax_nxt, s1_ay_nxt,
        s2_x_nxt, s2_y_nxt, s2_vx_nxt, s2_vy_nxt, s2_ax_nxt, s2_ay_nxt,
        s3_x_nxt, s3_y_nxt, s3_vx_nxt, s3_vy_nxt, s3_ax_nxt, s3_ay_nxt,
        fb_x_nxt, fb_y_nxt, fb_vx_nxt, fb_vy_nxt, fb_ax_nxt, fb_ay_nxt,
        pl_x_nxt, pl_y_nxt, pl_vx_nxt, pl_vy_nxt, pl_ax_nxt, pl_ay_nxt
    )

    # 4. return final state and rolling sum of bools
    return (
        s1_x_final, s1_y_final, s1_vx_final, s1_vy_final, s1_ax_final, s1_ay_final,
        s2_x_final, s2_y_final, s2_vx_final, s2_vy_final, s2_ax_final, s2_ay_final,
        s3_x_final, s3_y_final, s3_vx_final, s3_vy_final, s3_ax_final, s3_ay_final,
        fb_x_final, fb_y_final, fb_vx_final, fb_vy_final, fb_ax_final, fb_ay_final,
        pl_x_final, pl_y_final, pl_vx_final, pl_vy_final, pl_ax_final, pl_ay_final,
        rest_of_sum_broke_the_law + broke_the_law,
        rest_of_sum_scored_s1 + scored_s1,
        rest_of_sum_scored_s2 + scored_s2,
        rest_of_sum_scored_s3 + scored_s3
    )
end

#####################
## pseudocode below #
#####################
# def recur (state) -> (state_final, sum_final):
#     state_, bool = forward (state)
#     if state_.v == 0:
#         let state_stopped = state_
#         return (state_stopped, bool)

#     let (state_final, rest_of_sum) = recur (state_)
#     return (state_final, bool + rest_of_sum)
# end
