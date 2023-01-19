- Update the rewards of all liquidity pools
  - `massUpdatePools()`
  - update a pool


- who updates the `bonusEndBlock`?
  - It is related to ICO and bonus when the MasterChecf contract was in ICO period, where it is given bonus for initial investors.
  - It is the time until when the rewards will be applicable for all users of that LP.
  - Its value is set during contructor execution.


- pool.allocPoint vs sushiPerBlock

- 10% of rewards will go to devAddress


- Is Sushi the name given to reward or the LP token name?
  - There are 2 things to note,
  - One is the LP token of that LP pool
  - Other is the Sushi Token (rewards)

- How is user details (rewards) updated after LP token deposit.
  - `pool.accSushiPerShare` decides the reward amount which is calculated by first computing the total rewards / total LP token in that LP pool