# Physics puzzle on StarkNet

### Game mechanics
- 3 prize balls + 1 forbidden ball + 1 player-controlled ball all at preset positions at start.
- Player chooses angle and initial velocity within a range to strike the player-controlled ball.
- game rule is to touch as many prize balls in one strike without having the forbidden ball touched by any ball.
- alternate game rule: not counting how many prize ball touched by how many 'times' any prize ball is touched. different prize ball can have different score multiplier.

### StarkNet-based architecture

- **Inventory** contract
  - hardcoded physics puzzle configurations to be pulled by **manager**

- **Chef** contract
  - physics engine: receives one state from **server**, return state advanced by dt to **server**
  - constraints and constants supplied by **manager**, who pulls the constraint originally from **inventory**

- **Server** contract x N
  - each **server** manages the entire simulation and scoring for one gameplay
  - N == client cap because "each client in this establishment deserves a dedicated server"

- **Manager** contract
  - (for previous round) receives final states from clients and compares with client-submitted final states before inscribing final states to **shrine**; (for next round) accepts up to N client registrations.
  - retrieves level from **inventory** for client to query; receives client actions and calls one **server** per client to handle simulation;

- **Shrine** contract
  - receives records from **manager** and store records to scoreboard for all to worship
  
### Game loop
- Upon contract deployment, **Manager** pulls a level from the **Inventory** contract and stores in `Puzzle` (a struct; storage_var). The client polls `Puzzle` from **Manager** and render the puzzle on screen for player to see.
- Player makes a move (i.e. the velocity and angle to move the player-controlled ball; client UI TBD). The decision is sent by client to the **Manager** as a *transaction* - invoking `MakeMove()`, which stores the move in storage_var `Move`, and calls the **Server**'s `RunSimulation()` to serve this game given player's move.
- The **Server**'s `RunSimulation()`, a @view function, starts from the level's initial configuration, changes the player-controlled ball's velocity at t=0, and runs the simulation by calling **Chef**'s `EulerForward()` sequentially from t=0, dt, 2dt, ... until all balls are at rest i.e. zero velocity. Throughout the call, the **Server** also makes note of the collision report from **Chef** and calculate game scores accordingly. The **Server** then returns the final state of the puzzle (the positions of the balls at the end) plus game score to **Manager**.
- **Chef**'s `EulerForward` simply takes the state of the physics system at an arbitrary t and returns the state of the same system at t+dt i.e. it advances the system in time by dt. The **Chef** is the soul of the game code (as in restaurants IRL), doing the heavy-lifting of running the physics simulation. For game's requirement, the **Chef** also returns bools indicating if collision has occurred, and if so, between which pair of physics entities. This collision report is for game scoring purposes.
- Eventually, the **Manager**, still in function `MakeMove()`, receives the final state of the puzzle and game score from **Server**. The **Mananger** then does two things: invokes **Shrine**'s `InscribeRecord()` function to update the scoreboard with the current player's address, game score, puzzle level, and the final state of the puzzle. Finally, `MakeMove()` returns the game score and final state of the puzzle back to client.
- In short: client polls current puzzle from **Manager** => client invokes `MakeMove()` => **Manager** calls `RunSimulation()` => **Server** calls `EulerForward()` **Chef** sequentially until all balls stop => **Server** returns final puzzle state and score to **Manager** => **Manager** invokes `InscribeRecord`, pulls new puzzle from **Inventory** to store in itself, and returns final puzzle state and score to client.
