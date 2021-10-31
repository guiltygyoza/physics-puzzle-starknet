%lang starknet
%builtins pedersen range_check

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import (assert_not_zero)

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

struct GameState:
    member system_state : SystemState
    member cumulative_score : felt
end

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
    member puzzle_id : felt
end

@contract_interface
namespace IContractInventory:
    func pull_random_puzzle() -> (
        puzzle : Puzzle
        ):
    end
end

@contract_interface
namespace IContractServer:
    func run_simulation(
            puzzle_init : PuzzleState,
            ball_player_vx, ball_player_vy,
            chef_address
        ) -> (
            puzzle_final : PuzzleState,
            score,
            steps_took
        ):
    end

    func run_simulation_capped(
            system_state : SystemState,
            chef_address
        ) -> (
            system_state_final : SystemState,
            score,
            steps_took,
            bool_shall_end
        ):
    end
end

@contract_interface
namespace IContractShrine:
    func inscribe_record(
            puzzle_id : felt,
            player_address : felt,
            score : felt
        ) -> ():
    end
end

@storage_var
func CurrentPuzzle () -> (puzzle : Puzzle):
end

@storage_var
func StoredAddress (index : felt) -> (address : felt):
end

@storage_var
func HasUnfinishedGame () -> (bool : felt):
end

@storage_var
func StoredGameState () -> (stored_game_state : GameState):
end

#################################

@external
func admin_initialize_addresses {
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (
        inventory_address : felt,
        server_address : felt,
        chef_address : felt,
        shrine_address : felt
    ) -> ():

    ## Note: this function won't be needed when constructor and contract-deployment features are added by StarkWare
    StoredAddress.write (0, inventory_address)
    StoredAddress.write (1, server_address)
    StoredAddress.write (2, chef_address)
    StoredAddress.write (3, shrine_address)
    HasUnfinishedGame.write (0)

    return ()
end
#################################

@external
func admin_initialize_puzzle {
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } () -> ():

    let (inventory_address) = StoredAddress.read(0)
    let (puzzle : Puzzle) = IContractInventory.pull_random_puzzle (inventory_address)
    CurrentPuzzle.write (puzzle)
    return ()
end

#################################

@view
func client_pull_puzzle {
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } () -> (puzzle : Puzzle):

    let (puzzle) = CurrentPuzzle.read()
    return (puzzle)
end

#################################

@external
func MakeMove {
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (
        ball_player_vx : felt,
        ball_player_vy : felt
    ) -> (
        system_state : SystemState,
        score : felt,
        steps_took : felt,
        bool_finished : felt
    ):
    alloc_locals

    # read puzzle and assemble system_state_init
    let (local puzzle : Puzzle) = CurrentPuzzle.read()
    local system_state_init : SystemState = SystemState(
        BallState(puzzle.puzzle_state.ball_score1_x, puzzle.puzzle_state.ball_score1_y, 0, 0, 0, 0),
        BallState(puzzle.puzzle_state.ball_score2_x, puzzle.puzzle_state.ball_score2_y, 0, 0, 0, 0),
        BallState(puzzle.puzzle_state.ball_score3_x, puzzle.puzzle_state.ball_score3_y, 0, 0, 0, 0),
        BallState(puzzle.puzzle_state.ball_forbid_x, puzzle.puzzle_state.ball_forbid_y, 0, 0, 0, 0),
        BallState(puzzle.puzzle_state.ball_player_x, puzzle.puzzle_state.ball_player_y, ball_player_vx, ball_player_vy, 0, 0),
    )

    # fetch stored contract addresses
    let (local server_address) = StoredAddress.read(1)
    let (chef_address) = StoredAddress.read(2)

    # run the simulation
    let (
        local system_state : SystemState, local score, local steps_took, local bool_shall_end
    ) = IContractServer.run_simulation_capped (server_address, system_state_init, chef_address)

    # handle result depends on ending or not
    if bool_shall_end == 1:
        let (local puzzle : Puzzle) = CurrentPuzzle.read()
        let (shrine_address) = StoredAddress.read(3)
        IContractShrine.inscribe_record (shrine_address, puzzle.puzzle_id, 12345, score) # TODO: swap 0 with real puzzle id; 12345 with real player address

        let (inventory_address) = StoredAddress.read(0)
        let (new_puzzle : Puzzle) = IContractInventory.pull_random_puzzle (inventory_address)
        CurrentPuzzle.write (new_puzzle)
        HasUnfinishedGame.write(0)
    else:
        let game_state : GameState = GameState (
            system_state,
            score
        )
        StoredGameState.write(game_state)
        HasUnfinishedGame.write(1)
    end

    return (system_state, score, steps_took, bool_shall_end)
end

@external
func ContinueMove {
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } () -> (
        system_state : SystemState,
        score : felt,
        steps_took : felt,
        bool_finished : felt
    ):
    alloc_locals

    # calling ContinueMove without an unfinished game is not allowed
    let (bool) = HasUnfinishedGame.read()
    assert_not_zero(bool)

    # retrieve stored game state
    let (local last_game_state : GameState) = StoredGameState.read()

    # continue the simulation from stored state
    let (local server_address) = StoredAddress.read(1)
    let (chef_address) = StoredAddress.read(2)
    let (
        local system_state, local score, local steps_took, local bool_shall_end
    ) = IContractServer.run_simulation_capped (server_address, last_game_state.system_state, chef_address)

    # end simulation if finished; else store state
    # TODO refactor this with MakeMove()
    if bool_shall_end == 1:
        let (local puzzle : Puzzle) = CurrentPuzzle.read()
        let (shrine_address) = StoredAddress.read(3)
        IContractShrine.inscribe_record (shrine_address, puzzle.puzzle_id, 12345, score) # TODO: swap 0 with real puzzle id; 12345 with real player address

        let (inventory_address) = StoredAddress.read(0)
        let (new_puzzle : Puzzle) = IContractInventory.pull_random_puzzle (inventory_address)
        CurrentPuzzle.write (new_puzzle)
        HasUnfinishedGame.write(0)
    else:
        let game_state : GameState = GameState (
            system_state,
            score + last_game_state.cumulative_score
        )
        StoredGameState.write(game_state)
        HasUnfinishedGame.write(1)
    end

    return (
        system_state, score + last_game_state.cumulative_score, steps_took, bool_shall_end
    )
end

@view
func client_poll_if_manager_has_unfinished_game {
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } () -> (bool : felt):

    let (bool) = HasUnfinishedGame.read()
    return (bool)
end

@view
func admin_pull_stored_game_state {
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } () -> (stored_game_state : GameState):

    let (stored_game_state) = StoredGameState.read()
    return (stored_game_state)
end