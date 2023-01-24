- Interconnected contracts
  - done: EIP712Base (s)
  - NativeMetaTransaction
    - This make use of (inherits) EIP712Base contract to provide the service of meta transactions.
    - MetaTransaction() is only used when we want to perform transaction without send ETH "value". What is somebody sends `value`?
    - In the UniswapV2Router, this complete contract is manually copied.
    - this has a `executeMetaTransaction()` that is not checked properly.
      - YGNStaker.sol
        - d
      - YGN.sol
        - d
  - UniswapV2Router

  - YGNStaker

* Unit testing only
  - MasterChef (s)
  - WithdrawFeeFarm
  - FYGNClaimableBurner
  - LiquidityMigratorV1
  - FYGN
  - EthalendVaultsQuickSwapStrategy
  - QuickSwapFarmsStrategyDual
  - TarotSupplyVaultStrategy
  - CafeSwapStrategy
  - Farm
  - PenroseFinanceStrategy
  - QuickSwapFarmsStrategy
  - QuickSwapDragonSyrupStrategy
  - SushiSwapFarmsStrategy
  - NachoXYZStrategy
  - UniversalConverterHelper
  - RewardManager
  - UniversalConverter
  - RewardManagerFactory
  - DystConverter
  - SingleSidedLiquidityV2
  - Converter
  - FirstBuy
  - FTMWrapper
  - FarmWrapper

- Isolated contracts
  - TransferHelper
  - SafeMathUniswapV2 (s)
  - UniswapV2Library (s)


---------

1. Salt is not used in domain separator.
