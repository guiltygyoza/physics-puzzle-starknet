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
const ITER_CAP = 120

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
    member ball_score1 : BallState
    member ball_score2 : BallState
    member ball_score3 : BallState
    member ball_forbid : BallState
    member ball_player : BallState
end

## Contract interfaces
@contract_interface
namespace IContractChef:
    func euler_forward (
            state : SystemState,
            first : felt
        ) -> (
            state_nxt : SystemState,
            broke_the_law : felt,
            scored_s1 : felt,
            scored_s2 : felt,
            scored_s3 : felt
        ):
    end
end

#################################

# @external
# func run_simulation {
#         syscall_ptr : felt*,
#         range_check_ptr
#     } (
#         puzzle_state_init : PuzzleState,
#         ball_player_vx : felt, ball_player_vy : felt,
#         chef_address : felt
#     ) -> (
#         puzzle_final : PuzzleState,
#         score : felt,
#         steps_took : felt
#     ):
#     alloc_locals

#     local ball_score1 : BallState = BallState (
#         x = puzzle_state_init.ball_score1_x, y = puzzle_state_init.ball_score1_y,
#         vx = 0, vy = 0, ax = 0, ay = 0)

#     local ball_score2 : BallState = BallState(
#         x = puzzle_state_init.ball_score2_x, y = puzzle_state_init.ball_score2_y,
#         vx = 0, vy = 0, ax = 0, ay = 0)

#     local ball_score3 : BallState = BallState(
#         x = puzzle_state_init.ball_score3_x, y = puzzle_state_init.ball_score3_y,
#         vx = 0, vy = 0, ax = 0, ay = 0)

#     local ball_forbid : BallState = BallState(
#         x = puzzle_state_init.ball_forbid_x, y = puzzle_state_init.ball_forbid_y,
#         vx = 0, vy = 0, ax = 0, ay = 0)

#     local ball_player : BallState = BallState(
#         x = puzzle_state_init.ball_player_x, y = puzzle_state_init.ball_player_y,
#         vx = ball_player_vx, vy = ball_player_vy, ax = 0, ay = 0)

#     local system_state_init : SystemState = SystemState (
#         ball_score1, ball_score2, ball_score3, ball_forbid, ball_player)

#     ## Call euler_forward() recursively to complete simulation
#     let (
#         local system_state_final,
#         local sum_broke_the_law, local sum_scored_s1, local sum_scored_s2, local sum_scored_s3,
#         local steps_took
#     ) = _recurse_euler_forward (chef_address, system_state_init, 1)

#     # calculate score
#     let (safe) = is_zero (sum_broke_the_law)
#     tempvar tentative_score = sum_scored_s1 * SCORE_S1 + sum_scored_s2 * SCORE_S2 + sum_scored_s3 * SCORE_S3
#     let score = tentative_score * safe

#     ## assemble puzzle_final
#     let puzzle_state_final : PuzzleState = PuzzleState (
#         ball_score1_x = system_state_final.ball_score1.x,
#         ball_score1_y = system_state_final.ball_score1.y,
#         ball_score2_x = system_state_final.ball_score2.x,
#         ball_score2_y = system_state_final.ball_score2.y,
#         ball_score3_x = system_state_final.ball_score3.x,
#         ball_score3_y = system_state_final.ball_score3.y,
#         ball_forbid_x = system_state_final.ball_forbid.x,
#         ball_forbid_y = system_state_final.ball_forbid.y,
#         ball_player_x = system_state_final.ball_player.x,
#         ball_player_y = system_state_final.ball_player.y
#     )

#     return (puzzle_state_final, score, steps_took)
# end

@external
func run_simulation_capped {
        syscall_ptr : felt*,
        range_check_ptr
    } (
        system_state : SystemState,
        chef_address : felt
    ) -> (
        system_state_final : SystemState,
        score : felt,
        steps_took : felt,
        bool_shall_end : felt
    ):
    alloc_locals

    ## Call euler_forward() recursively to complete simulation
    let (
        local system_state_final,
        local sum_broke_the_law, local sum_scored_s1, local sum_scored_s2, local sum_scored_s3,
        local steps_took,
        local final_bool_finished
    ) = _recurse_euler_forward_capped (chef_address=chef_address, state=system_state, first=1, iter=0, bool_finished=0)

    # calculate score
    let (safe) = is_zero (sum_broke_the_law)
    tempvar tentative_score = sum_scored_s1 * SCORE_S1 + sum_scored_s2 * SCORE_S2 + sum_scored_s3 * SCORE_S3
    let score = tentative_score * safe

    # simulation shall end if law is broken - no need to run the rest of the simulation
    # TODO: should move this detection to the recursion - stop recursion when the law is broken
    local bool_shall_end
    if safe==0:
        assert bool_shall_end = 1
    else:
        assert bool_shall_end = final_bool_finished
    end

    return (system_state_final, score, steps_took, bool_shall_end)
end

# func _recurse_euler_forward {
#         syscall_ptr : felt*,
#         range_check_ptr
#     }(
#         chef_address : felt,
#         state : SystemState,
#         first : felt
#     ) -> (
#         state_final : SystemState,
#         sum_broke_the_law : felt, sum_scored_s1 : felt, sum_scored_s2 : felt, sum_scored_s3 : felt,
#         steps_took : felt
#     ):
#     alloc_locals

#     # 1. calculate forward
#     let (
#         local state_nxt : SystemState,
#         local broke_the_law, local scored_s1, local scored_s2, local scored_s3
#     ) = IContractChef.euler_forward (
#         chef_address,
#         state,
#         first
#     )

#     # 2. return if reached final state TODO: user array of struct to be able to loop over all velocity components
#     let (local s1_vx_nxt_abs) = abs_value (state_nxt.ball_score1.vx)
#     let (local s1_vy_nxt_abs) = abs_value (state_nxt.ball_score1.vy)
#     let (local s2_vx_nxt_abs) = abs_value (state_nxt.ball_score2.vx)
#     let (local s2_vy_nxt_abs) = abs_value (state_nxt.ball_score2.vy)
#     let (local s3_vx_nxt_abs) = abs_value (state_nxt.ball_score3.vx)
#     let (local s3_vy_nxt_abs) = abs_value (state_nxt.ball_score3.vy)
#     let (local fb_vx_nxt_abs) = abs_value (state_nxt.ball_forbid.vx)
#     let (local fb_vy_nxt_abs) = abs_value (state_nxt.ball_forbid.vy)
#     let (local pl_vx_nxt_abs) = abs_value (state_nxt.ball_player.vx)
#     let (pl_vy_nxt_abs) = abs_value (state_nxt.ball_player.vy)
#     let v_abs_sum = s1_vx_nxt_abs + s1_vy_nxt_abs + s2_vx_nxt_abs + s2_vy_nxt_abs + s3_vx_nxt_abs + s3_vy_nxt_abs + fb_vx_nxt_abs + fb_vy_nxt_abs + pl_vx_nxt_abs + pl_vy_nxt_abs

#     if v_abs_sum == 0:
#         return(
#             state_nxt,
#             broke_the_law, scored_s1, scored_s2, scored_s3,
#             1
#         )
#     end

#     # 3. otherwise, recurse
#     let (
#         state_final : SystemState,
#         rest_of_sum_broke_the_law, rest_of_sum_scored_s1, rest_of_sum_scored_s2, rest_of_sum_scored_s3,
#         rest_of_steps
#     ) = _recurse_euler_forward (
#         chef_address,
#         state_nxt,
#         0
#     )

#     # 4. return final state and rolling sum of bools
#     return (
#         state_final,
#         rest_of_sum_broke_the_law + broke_the_law,
#         rest_of_sum_scored_s1 + scored_s1,
#         rest_of_sum_scored_s2 + scored_s2,
#         rest_of_sum_scored_s3 + scored_s3,
#         rest_of_steps + 1
#     )
# end

func _recurse_euler_forward_capped {
        syscall_ptr : felt*,
        range_check_ptr
    }(
        chef_address : felt,
        state : SystemState,
        first : felt,
        iter : felt,
        bool_finished : felt
    ) -> (
        state_final : SystemState,
        sum_broke_the_law : felt, sum_scored_s1 : felt, sum_scored_s2 : felt, sum_scored_s3 : felt,
        steps_took : felt,
        final_bool_finished : felt
    ):
    alloc_locals

    # 1. calculate forward
    let (
        local state_nxt : SystemState,
        local broke_the_law, local scored_s1, local scored_s2, local scored_s3
    ) = IContractChef.euler_forward (
        chef_address,
        state,
        first
    )

    # 2. return if reached final state TODO: user array of struct to be able to loop over all velocity components
    let (local s1_vx_nxt_abs) = abs_value (state_nxt.ball_score1.vx)
    let (local s1_vy_nxt_abs) = abs_value (state_nxt.ball_score1.vy)
    let (local s2_vx_nxt_abs) = abs_value (state_nxt.ball_score2.vx)
    let (local s2_vy_nxt_abs) = abs_value (state_nxt.ball_score2.vy)
    let (local s3_vx_nxt_abs) = abs_value (state_nxt.ball_score3.vx)
    let (local s3_vy_nxt_abs) = abs_value (state_nxt.ball_score3.vy)
    let (local fb_vx_nxt_abs) = abs_value (state_nxt.ball_forbid.vx)
    let (local fb_vy_nxt_abs) = abs_value (state_nxt.ball_forbid.vy)
    let (local pl_vx_nxt_abs) = abs_value (state_nxt.ball_player.vx)
    let (pl_vy_nxt_abs) = abs_value (state_nxt.ball_player.vy)
    let v_abs_sum = s1_vx_nxt_abs + s1_vy_nxt_abs + s2_vx_nxt_abs + s2_vy_nxt_abs + s3_vx_nxt_abs + s3_vy_nxt_abs + fb_vx_nxt_abs + fb_vy_nxt_abs + pl_vx_nxt_abs + pl_vy_nxt_abs

    local bool_finished
    if v_abs_sum == 0:
        assert bool_finished = 1
        return(
            state_final = state_nxt,
            sum_broke_the_law = broke_the_law,
            sum_scored_s1 = scored_s1,
            sum_scored_s2 = scored_s2,
            sum_scored_s3 = scored_s3,
            steps_took = 1,
            final_bool_finished = bool_finished
        )
    else:
        # 3. return if iteration cap reached
        assert bool_finished = 0
        local iter_ = iter + 1
        tempvar iter_left = ITER_CAP - iter_
        if iter_left == 0:
            return(
                state_final = state_nxt,
                sum_broke_the_law = broke_the_law,
                sum_scored_s1 = scored_s1,
                sum_scored_s2 = scored_s2,
                sum_scored_s3 = scored_s3,
                steps_took = 1,
                final_bool_finished = bool_finished
            )
        end
    end

    # 4. all good? recurse
    let (
        state_final : SystemState,
        rest_of_sum_broke_the_law, rest_of_sum_scored_s1, rest_of_sum_scored_s2, rest_of_sum_scored_s3,
        rest_of_steps,
        final_bool_finished
    ) = _recurse_euler_forward_capped (
        chef_address,
        state_nxt,
        0,
        iter_,
        bool_finished
    )

    # 5. return final state and rolling sum of bools
    return (
        state_final,
        rest_of_sum_broke_the_law + broke_the_law,
        rest_of_sum_scored_s1 + scored_s1,
        rest_of_sum_scored_s2 + scored_s2,
        rest_of_sum_scored_s3 + scored_s3,
        rest_of_steps + 1,
        final_bool_finished
    )
end