# Physics puzzle on StarkNet
<img width="391" alt="screenshot" src="https://user-images.githubusercontent.com/59590480/139565734-b946166f-df2c-4d5d-95e6-3085a81f2f0c.png">

### Game mechanics

- 3 prize balls + 1 forbidden ball (gray) + 1 player-controlled ball (white) all at preset locations at start determined by puzzle id.
- Player chooses initial velocity - both x and y component, within legal range - to strike the player-controlled ball.
- Rule of the game is to touch as many prize balls in one strike with the player-controlled ball with the forbidden ball untouched by any ball. If the forbidden ball is touch, score is 0; the prize balls have different score multipliers.
- Alternate game rule: not counting how many prize ball touched, but by how many 'times' any prize ball is touched.

### StarkNet-based architecture

- **Inventory** contract
  - hardcoded physics puzzle configurations to be pulled by **manager** pseudorandomly

- **Chef** contract
  - the physics engine: receives one state from **server**, return state advanced by `dt` to **server**
  - currently has hardcoded constant constraints (ball radius, boundary location etc).

- **Server** contract
  - manages the entire simulation and scoring for one gameplay
  - calls **Chef** to advance state recursively until either stopping condition reached or maximum iteration cap reached, whichever comes first
  - maximum iteration cap is to avoid the transaction exhausting available StarkNet execution resource (estimated to be 1,000,000 `n_steps` per tx); one long simulation is broken up to multiple transactions to complete.

- **Manager** contract
  - retrieves level from **inventory** for client to query; receives client actions and calls one **server** per client to handle simulation;
  - saves unfinished simulation for later transcations to continue
  - inscribing records to **shrine**

- **Shrine** contract
  - receives records from **manager** and store records to scoreboard for all to worship
  
### Game loop
- Upon contract deployment, **Manager** pulls a level from the **Inventory** contract and stores in `Puzzle` (a struct; storage_var). The client polls `Puzzle` from **Manager** and render the puzzle on screen for player to see.
- Player makes a move (i.e. the x and y component of the initial velocity of the player-controlled ball). The decision is sent by client to the **Manager** as a *transaction* - invoking `MakeMove()`, which calls the **Server**'s `RunSimulation()` to serve this game given player's move.
- The **Server**'s `RunSimulation()`, a @view function, starts from the level's initial configuration, changes the player-controlled ball's velocity at t=0, and runs the simulation by calling **Chef**'s `EulerForward()` sequentially from t=0, dt, 2dt, ... until all balls are at rest i.e. zero velocity. Throughout the call, the **Server** also makes note of the collision report from **Chef** and calculate game scores accordingly. The **Server** then returns the final state of the puzzle (the positions of the balls at the end) plus game score to **Manager**.
- **Chef**'s `EulerForward` simply takes the state of the physics system at an arbitrary t and returns the state of the same system at t+dt i.e. it advances the system in time by dt. The **Chef** is the soul of the game code (as in restaurants IRL), doing the heavy-lifting of running the physics simulation. For game's requirement, the **Chef** also returns bools indicating if collision has occurred, and if so, between which pair of physics entities. This collision report is for game scoring purposes. Note: funky tricks are used to avoid recalculate friction to reduce computation
- Eventually, the **Manager**, still in function `MakeMove()`, receives the final state of the puzzle and game score from **Server**. The **Mananger** then does two things: invokes **Shrine**'s `InscribeRecord()` function to update the scoreboard with the current player's address, game score, and puzzle id. Finally, `MakeMove()` returns the game score and final state of the puzzle back to client.
- In short: client polls current puzzle from **Manager** => client invokes `MakeMove()` => **Manager** calls `RunSimulation()` => **Server** calls `EulerForward()` **Chef** sequentially until all balls stop => **Server** returns final puzzle state and score to **Manager** => **Manager** invokes `InscribeRecord`, pulls new puzzle from **Inventory** to store in itself, and returns final puzzle state and score to client.

TODO:
- too many things yet to be done. one would be implementing insertion sort for **shrine**'s scoreboard.
- more puzzles please!
- perhaps balls of different sizes
- make the boundary not axis-aligned
