%lang starknet
%builtins pedersen range_check

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import (unsigned_div_rem, split_felt)

const SCALE_FP = 100*100

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

struct Puzzle:
    member puzzle_state : PuzzleState
    member puzzle_level : felt
end

# Seed for pseudorandom
@storage_var
func entropy_seed() -> (value : felt):
end

## TODO: add either storage_var for updating puzzles (have to make sure append-only)
##       or hard-coded dictionary storing all the preconceived puzzles

@external
func initialize_seed{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(seed : felt) -> ():

    entropy_seed.write(seed)

    return ()
end

@external
func get_pseudorandom{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (
        num : felt
    ):
    # Seed is fed to linear congruential generator.
    # seed = (multiplier * seed + increment) % modulus.
    # Params from GCC. (https://en.wikipedia.org/wiki/Linear_congruential_generator).
    let (old_seed) = entropy_seed.read()
    # Snip in half to a manageable size for unsigned_div_rem.
    let (left, right) = split_felt(old_seed)
    let (_, new_seed) = unsigned_div_rem(1103515245 * right + 1, 2**31)

    # Number has form: 10**9 (xxxxxxxxxx).
    # Should be okay to write multiple times to same variable
    # without increasing storage costs of this transaction.
    entropy_seed.write(new_seed)

    return (new_seed)
end

@external
func get_pseudorandom_mod2{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (num : felt):

    let (prand_num) = get_pseudorandom()
    let (_, num) = unsigned_div_rem(prand_num, 2)

    return (num)
end


@external
func pull_random_puzzle {
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } () -> (
        puzzle : Puzzle
    ):
    alloc_locals

    # TODO: use better data structure to initialize the puzzles

    let (local id) = get_pseudorandom_mod2()

    local puzzle_state : PuzzleState
    if id == 0:
        assert puzzle_state = PuzzleState (
            300 * SCALE_FP, 250 * SCALE_FP,
            200 * SCALE_FP, 250 * SCALE_FP,
            100 * SCALE_FP, 250 * SCALE_FP,
            200 * SCALE_FP, 350 * SCALE_FP,
            200 * SCALE_FP, 100 * SCALE_FP
        )
    else:
        assert puzzle_state = PuzzleState (
            80 * SCALE_FP, 130 * SCALE_FP,
            140 * SCALE_FP, 340 * SCALE_FP,
            300 * SCALE_FP, 300 * SCALE_FP,
            230 * SCALE_FP, 150 * SCALE_FP,
            180 * SCALE_FP, 60 * SCALE_FP
        )
    end

    let puzzle : Puzzle = Puzzle (
        puzzle_state,
        id
    )

    return (puzzle)
end
