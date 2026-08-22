# kOS-GFOLD addon

## GFOLD Algorithm

kOS-GFOLD is a addon that enables lossless convex optimization of optimal landing trajectory programming. It takes in neccessary constraints and output optimal trajectory. Then user can follow the trajectory with pure kOS codes

Read neccessary papers to learn about GFOLD: `./references/*.pdf`. If you search the internet and find other good papers, you can read them too. (but I think these two are enough for your work).

In the formulation of the optimal landing program defined by these 2 papers, several contraints are already included

- Engine thrust (relaxed by the slack variable)
- Fuel consumption
- Maximum speed during flight
- Tilt angle (the angle between thrust vector and up axis)
- Glide slope contraint

I want you to add another 2 constraints, which is easily to be expressed in convex form

- Equality constraint: The terminal thrust vector (size and direction): This is to ensure the landing attitude is pointing up (How do you think of the neccessarity of this constraint?)
- Inequality constraint: **Thrust changing rate**. The time deriative of the thrust magnitude should not exceed threshold $\dot{\Gamma} = (\Gamma_{k+1} - \Gamma_{k})/\Delta t_k < \dot{\Gamma}_{max}, \dot{\Gamma} > -\dot{\Gamma}_{max}$. This is to ensure that the throttle can catch up with command
- Inequality constraint: **Attitude changing rate**. The rotation speed of the thrust direction should not exceed threshold. This is to ensure that the attitude control can follow the command

If you find out that some other contraints which can benefit landing, you can add it.

And the paper by Neal 2016, introduced pit landing method. It split the trajectory into 2 parts, with different glide slope and tilt constraints, the split time is to be optimized. I need this feature too.

Another problem is the changing thrust constraint. In some reusable rocket designs, it may switch engines when approaching target. For example, the New Glenn rocket ignites 3 engines, upon approaching target, it shutdown 2 side engines and keeps only the center engine running. This introduce a thrust constraint change during landing. I want to design like this, the user provides the running time of the first part ($t_c$) and thrust constraints of 2 parts. When $t < t_c$ the first thrust constraints are applied to nodes, and when $t >= t_1$, the second thrust constraints are applied. By explicitly assign $t_1$, the problem is still convex.

## Requirements

Implement a GFOLD addon for kOS. You need to design the architecture and APIs. Here I states some requirements

Reference Frame: Body fixed frame, origin point at body center

Program Input

- Body parameters: gravity, radius, body spin (as a omega vector)
- Initial conditions: initial mass, position, velocity (body-fixed frame)
- Target conditions: position, velocity and thrust vector at target, 
- Fuel constraint: Fuel mass
- Thrust constraints: 2 parts, $\rho_1^{(1)}, \rho_2^{(1)}, \rho_1^{(2)}, \rho_2^{(2)}$, and switching time $t_c$
- Speed, tilt, glide slope, thrust changing rate, attitude changing rate: assigned for 2 phases, the phase time is to be optimized
- Number of nodes

Program Output

- Solving state: time used and status
- Phase time (when to enter pit region)
- Trajectory: Position, velocity, thrust and time at each node

Implementation Requirements

- The optimization should be run in background thread (like how kOS-AFS did it), otherwise it will jam the game
- For 20 nodes, the calculation should not take longer than 2 seconds. And the faster the better. Compare the speed, maintaince cost and other features for ECOS and Alglib, choose one solver to do this job

## Plan

1. Read the paper and other requirements, analyze feasibility, improve the plan, derive the math representation of this problem, write it to `Formulation.md`. Note that SOCP solvers like variables to be in proper range, avoiding too large and too low values, you need to normalize this variables to make the solver happy
2. Decide which solver to use and program architecture
3. Implement the addon
