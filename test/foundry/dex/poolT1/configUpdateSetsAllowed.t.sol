// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { PoolT1BaseTest } from "./pool.t.sol";
import { FluidDexT1Admin } from "../../../../contracts/protocols/dex/poolT1/adminModule/main.sol";
import { Structs as DexAdminStructs } from "../../../../contracts/protocols/dex/poolT1/adminModule/structs.sol";

/// @dev `updateUser*Configs` writes `allowed = 1`, so a config update activates a new user and re-enables a paused
///      one. Deployed pools are immutable and behave this way; re-pausing after a limit change is the pause auth's job.
contract FluidDexT1ConfigUpdateSetsAllowedTest is PoolT1BaseTest {
    address internal freshUser;

    function setUp() public virtual override {
        super.setUp();
        freshUser = address(0xD01FADE);
        _makeUserContract(freshUser, true);
    }

    function test_updateUserSupplyConfigs_newUser_setsAllowed() public {
        assertFalse(_getDexSupplyData(DAI_USDC.dexColDebt, freshUser).isUserAllowed);

        vm.prank(admin);
        FluidDexT1Admin(address(DAI_USDC.dexColDebt)).updateUserSupplyConfigs(_supplyCfg(freshUser));

        assertTrue(_getDexSupplyData(DAI_USDC.dexColDebt, freshUser).isUserAllowed);
    }

    function test_updateUserSupplyConfigs_pausedUser_isReactivated() public {
        vm.prank(admin);
        FluidDexT1Admin(address(DAI_USDC.dexColDebt)).updateUserSupplyConfigs(_supplyCfg(freshUser));
        vm.prank(admin);
        FluidDexT1Admin(address(DAI_USDC.dexColDebt)).pauseUser(freshUser, true, false);
        assertFalse(_getDexSupplyData(DAI_USDC.dexColDebt, freshUser).isUserAllowed);

        vm.prank(admin);
        FluidDexT1Admin(address(DAI_USDC.dexColDebt)).updateUserSupplyConfigs(_supplyCfg(freshUser));

        assertTrue(_getDexSupplyData(DAI_USDC.dexColDebt, freshUser).isUserAllowed);
    }

    function test_updateUserBorrowConfigs_newUser_setsAllowed() public {
        assertFalse(_getDexBorrowData(DAI_USDC.dexColDebt, freshUser).isUserAllowed);

        vm.prank(admin);
        FluidDexT1Admin(address(DAI_USDC.dexColDebt)).updateUserBorrowConfigs(_borrowCfg(freshUser));

        assertTrue(_getDexBorrowData(DAI_USDC.dexColDebt, freshUser).isUserAllowed);
    }

    function test_updateUserBorrowConfigs_pausedUser_isReactivated() public {
        vm.prank(admin);
        FluidDexT1Admin(address(DAI_USDC.dexColDebt)).updateUserBorrowConfigs(_borrowCfg(freshUser));
        vm.prank(admin);
        FluidDexT1Admin(address(DAI_USDC.dexColDebt)).pauseUser(freshUser, false, true);
        assertFalse(_getDexBorrowData(DAI_USDC.dexColDebt, freshUser).isUserAllowed);

        vm.prank(admin);
        FluidDexT1Admin(address(DAI_USDC.dexColDebt)).updateUserBorrowConfigs(_borrowCfg(freshUser));

        assertTrue(_getDexBorrowData(DAI_USDC.dexColDebt, freshUser).isUserAllowed);
    }

    function _supplyCfg(address user_) internal view returns (DexAdminStructs.UserSupplyConfig[] memory cfgs_) {
        cfgs_ = new DexAdminStructs.UserSupplyConfig[](1);
        cfgs_[0] = DexAdminStructs.UserSupplyConfig({
            user: user_,
            expandPercent: DEFAULT_EXPAND_WITHDRAWAL_LIMIT_PERCENT,
            expandDuration: DEFAULT_EXPAND_WITHDRAWAL_LIMIT_DURATION,
            baseWithdrawalLimit: DEFAULT_BASE_WITHDRAWAL_LIMIT * 100
        });
    }

    function _borrowCfg(address user_) internal view returns (DexAdminStructs.UserBorrowConfig[] memory cfgs_) {
        cfgs_ = new DexAdminStructs.UserBorrowConfig[](1);
        cfgs_[0] = DexAdminStructs.UserBorrowConfig({
            user: user_,
            expandPercent: DEFAULT_EXPAND_DEBT_CEILING_PERCENT,
            expandDuration: DEFAULT_EXPAND_DEBT_CEILING_DURATION,
            baseDebtCeiling: DEFAULT_BASE_DEBT_CEILING,
            maxDebtCeiling: DEFAULT_MAX_DEBT_CEILING * 100
        });
    }
}
