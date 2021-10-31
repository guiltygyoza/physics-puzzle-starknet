%lang starknet
%builtins pedersen range_check

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math_cmp import (is_le)

@storage_var
func Record (puzzle_id : felt, player_address : felt) -> (score : felt):
end

@view
func view_record {
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        puzzle_id : felt,
        player_address : felt
    ) -> (score):

    let (score) = Record.read(puzzle_id, player_address)
    return (score)
end

@external
func inscribe_record {
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        puzzle_id : felt,
        player_address : felt,
        score : felt
    ) -> ():
    alloc_locals

    # TODO: only the Manager can write to this record!
    # TODO: implement sorting algorithm for scoreboard
    let (prev_score) = Record.read(puzzle_id, player_address)

    local syscall_ptr : felt* = syscall_ptr
    local pedersen_ptr : HashBuiltin* = pedersen_ptr

    let (bool) = is_le (score, prev_score)
    if bool == 0:
        # score > prev_score => update record pls
        Record.write (puzzle_id, player_address, score)
        tempvar syscall_ptr = syscall_ptr
        tempvar pedersen_ptr = pedersen_ptr
        tempvar range_check_ptr = range_check_ptr
    else:
        tempvar syscall_ptr = syscall_ptr
        tempvar pedersen_ptr = pedersen_ptr
        tempvar range_check_ptr = range_check_ptr
    end

    return ()
end