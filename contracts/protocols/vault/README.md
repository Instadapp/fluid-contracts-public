# Fluid Vaults

## Factory

Factory deploys all the different vault Types. There are total of 4 vault Types:
Type 1: Normal Collateral & Normal Debt
Type 2: Smart Collateral & Normal Debt
Type 3: Normal Collateral & Smart Debt
Type 4: Smart Collateral & Smart Debt

VaultT1_not_for_prod: This vault works exactly same as VaultT1 but follows the common standard of VaultT2, VaultT3 & VaultT4 so is less gas efficient than VaultT1. This vault is created so we can run all the same old tests on the new vault infra to verify everything is setup perfectly fine.

### Deployment process for VaultT1:

0. Pre-deploy coreModule/main2.sol & adminModule/main.sol (These 2 will be same for all vaults so no need to redeploy for each vault)
1. Deploy coreModule/main.sol (Will be passing the above 2 addresses with all other addresses)
2. Setup configs using fallback which directs the call to adminModule. Initial setup to make vault usable needs: updateCoreSettings() & updateOracle(). updateRebalancer() is optional if not set then we cannot use rebalance() function, we can set it later on anytime.

### Deployment process for VaultT1_not_for_prod, VaultT2, VaultT3, VaultT4:

0. Pre-deploy coreModule/main2.sol & libraries/deployer.sol (These will be same for all vaults so no need to redeploy for each vault)
1. Deploy adminModule/main.sol (This we need to deploy once for each vault type)
2. Deploy coreModule/mainOperate.sol (This we need to deploy once for each vault with same contructor args as point 3). Construtor will be all the above 3 addresses with other configs. This `operateImplementation` in contructor should be sent as address(0) because this is the contract that we are deploying
3. Deploy coreModule/main.sol. Pass exact same args in contructor as above but change `operateImplementation` with the addresses we got on deploying 2 (coreModule/mainOperate.sol)
4. Setup configs using fallback which directs the call to adminModule. Initial setup to make vault usable needs: updateCoreSettings() & updateOracle(). updateRebalancer() is optional if not set then we cannot use rebalance() function, we can set it later on anytime.
