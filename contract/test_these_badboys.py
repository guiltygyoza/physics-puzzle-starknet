import pytest
import os
import re
from typing import Tuple

#from starkware.starknet.testing.starknet import Starknet
from starkware.starknet.compiler.compile import compile_starknet_files
from starkware.starknet.testing.contract import StarknetContract
from starkware.starknet.testing.state import StarknetState

SCALE_FP = 100*100
PRIME = 3618502788666131213697322783095070105623107215331596699973092056135872020481
PRIME_HALF = PRIME//2

@pytest.mark.asyncio
async def test_the_manager ():
    #starknet = await Starknet.empty()
    state = await StarknetState.empty()
    print()

    contract_s = {}
    contract_names = ['chef', 'server', 'inventory', 'shrine', 'manager']
    for name in contract_names:
        contract_def = compile_starknet_files([f'{name}.cairo'], debug_info=True)
        contract_adr = await state.deploy(
            constructor_calldata=[],
            contract_definition=contract_def
        )
        contract = StarknetContract(
            state=state, abi=contract_def.abi, contract_address=contract_adr
        )
        print(f'> {name}.cairo deployed.')
        contract_s[name] = contract
    print()

    ### Initialize manager contract
    await contract_s['manager'].admin_initialize_addresses (
        inventory_address = contract_s['inventory'].contract_address,
        server_address    = contract_s['server'].contract_address,
        chef_address      = contract_s['chef'].contract_address,
        shrine_address    = contract_s['shrine'].contract_address
    ).invoke()
    print(f"> Manager: admin_initialize_addresses() completed.")

    await contract_s['manager'].admin_initialize_puzzle().invoke()
    print(f"> Manager: admin_initialize_puzzle() completed.")
    print()

    ret = await contract_s['manager'].client_pull_puzzle().call()
    print(f"> Manager: client_pull_puzzle() returned: {ret.result}")
    print()
    puzzle_id = ret.result.puzzle.puzzle_id

    ## I already the good moves here
    if puzzle_id == 0:
        pl_vx = 190 *SCALE_FP
        pl_vy = 240 *SCALE_FP
    else:
        # currently only two puzzles
        pl_vx = -100 *SCALE_FP
        pl_vy = -230 *SCALE_FP

    # testing framework currently does not accept negative args; must perform mod P ourselves
    pl_vx = pl_vx % PRIME
    pl_vy = pl_vy % PRIME

    # Make the move!
    ret = await contract_s['manager'].MakeMove(pl_vx, pl_vy).invoke()
    print(f'> manager.MakeMove({pl_vx}, {pl_vy}) returned: {ret.result}')
    print()

    # Continue the move if the game is unfinished (simulation divided to multiple transactions to work with execution resource constraint)
    while (True):
        ret = await contract_s['manager'].client_poll_if_manager_has_unfinished_game().call()
        has_unfinished_game = int(ret.result.bool)
        if has_unfinished_game==1:
            print('> has unfinished game. calling ContinueMove()')

            ret = await contract_s['manager'].ContinueMove().invoke()
            print(f'manager.ContinueMove() returned: {ret.result}')
            print()
        else:
            print('> game has finished.')
            break

    ### Testing shrine contract
    ret = await contract_s['shrine'].view_record(puzzle_id=puzzle_id, player_address=12345).call()
    print(f'shrine.view_record(1, 12345) returned: {ret.result}')
    assert ret.result.score == 45 # <== I know this score

    ################################################

    ### Construct puzzle state for testing server / chef contract
    # puzzle_state_in = contract_s['server'].PuzzleState(
    #     ball_score1_x = 300*SCALE_FP, ball_score1_y = 250*SCALE_FP,
    #     ball_score2_x = 200*SCALE_FP, ball_score2_y = 250*SCALE_FP,
    #     ball_score3_x = 100*SCALE_FP, ball_score3_y = 250*SCALE_FP,
    #     ball_forbid_x = 200*SCALE_FP, ball_forbid_y = 350*SCALE_FP,
    #     ball_player_x = 200*SCALE_FP, ball_player_y = 100*SCALE_FP)

    ### Testing server + chef contract
    # vx = 0
    # vy = 204 * SCALE_FP
    # print(f'> testing run_simulation() with vx=0 and positive vy at start.')
    # ret = await contract_s['server'].run_simulation(puzzle_state_in, vx, vy, contract_s['chef'].contract_address).call()
    # print(f'> run_simulation() returned: {ret}')
    # print()

    ### Testing standalone chef contract
    # contract = contract_s['chef']
    # print(f'> testing euler_forward()')
    # vx0 = 190 * SCALE_FP
    # vy0 = 240 * SCALE_FP
    # state_init = contract.SystemState (
    #     ball_score1 = contract.BallState(x=300*SCALE_FP, y=250*SCALE_FP, vx=0, vy=0, ax=0, ay=0),
    #     ball_score2 = contract.BallState(x=200*SCALE_FP, y=250*SCALE_FP, vx=0, vy=0, ax=0, ay=0),
    #     ball_score3 = contract.BallState(x=100*SCALE_FP, y=250*SCALE_FP, vx=0, vy=0, ax=0, ay=0),
    #     ball_forbid = contract.BallState(x=200*SCALE_FP, y=350*SCALE_FP, vx=0, vy=0, ax=0, ay=0),
    #     ball_player = contract.BallState(x=200*SCALE_FP, y=100*SCALE_FP, vx=vx0, vy=vy0, ax=0, ay=0)
    # )
    # state = state_init
    # first = 1
    # for i in range(151):
    #     print(f'step:{i}')
    #     ret = await contract.euler_forward(state, first).call()
    #     print_system_state(ret.result.state_nxt)
    #     print()
    #     first = 0
    #     state = ret.result.state_nxt

def print_system_state(state):
    print_ball_state(state.ball_score1)
    print_ball_state(state.ball_score2)
    print_ball_state(state.ball_score3)
    print_ball_state(state.ball_forbid)
    print_ball_state(state.ball_player)

def print_ball_state(state):
    x = adjust_negative(state.x) / SCALE_FP
    y = adjust_negative(state.y) / SCALE_FP
    vx = adjust_negative(state.vx) / SCALE_FP
    vy = adjust_negative(state.vy) / SCALE_FP
    ax = adjust_negative(state.ax) / SCALE_FP
    ay = adjust_negative(state.ay) / SCALE_FP
    print(f'x={x}, y={y}, vx={vx}, vy={vy}, ax={ax}, ay={ay}')

def adjust_negative(e):
    if e > PRIME_HALF:
        return e-PRIME
    else:
        return e