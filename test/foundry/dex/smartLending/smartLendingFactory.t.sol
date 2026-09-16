//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { LibString } from "solmate/src/utils/LibString.sol";
import { IFluidLiquidityLogic } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";
import { MockOracle } from "../../../../contracts/mocks/mockOracle.sol";
import { IFluidLiquidity } from "../../../../contracts/liquidity/interfaces/iLiquidity.sol";

import { FluidDexT1 } from "../../../../contracts/protocols/dex/poolT1/coreModule/core/main.sol";
import { Error as FluidDexErrors } from "../../../../contracts/protocols/dex/error.sol";
import { ErrorTypes as FluidDexTypes } from "../../../../contracts/protocols/dex/errorTypes.sol";

import { FluidDexT1Admin } from "../../../../contracts/protocols/dex/poolT1/adminModule/main.sol";
import { Structs as DexStructs } from "../../../../contracts/protocols/dex/poolT1/coreModule/structs.sol";
import { Structs as DexAdminStructs } from "../../../../contracts/protocols/dex/poolT1/adminModule/structs.sol";
import { FluidContractFactory } from "../../../../contracts/deployer/main.sol";

import "../../testERC20.sol";
import "../../testERC20Dec6.sol";
import { FluidLendingRewardsRateModel } from "../../../../contracts/protocols/lending/lendingRewardsRateModel/main.sol";

import { FluidLiquidityUserModule } from "../../../../contracts/liquidity/userModule/main.sol";

import { FluidSmartLendingFactory, Events } from "contracts/protocols/dex/smartLending/factory/main.sol";
import { FluidSmartLending } from "contracts/protocols/dex/smartLending/main.sol";

contract SmartLendingFactoryTest is Test, Events {
    FluidSmartLendingFactory public smartLendingFactory;

    address public constant TEAM_MULTISIG = 0x4F6F977aCDD1177DCD81aB83074855EcB9C2D49e;

    address public constant DEX_WSTETH_ETH = 0x0B1a513ee24972DAEf112bC777a5610d4325C9e7;
    address public constant DEX_USDC_USDT = 0x667701e51B4D1Ca244F17C78F7aB8744B4C99F9B;

    address public constant DEX_FACTORY = 0x91716C4EDA1Fb55e84Bf8b4c7085f84285c19085;

    address public constant LIQUIDITY = 0x52Aa899454998Be5b000Ad077a46Bbe360F4e497;

    address alice = makeAddr("alice");
    address owner = makeAddr("owner");
    address deployer = makeAddr("deployer");
    address smartLending = makeAddr("smartLending");

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 21638485);

        smartLendingFactory = new FluidSmartLendingFactory(DEX_FACTORY, LIQUIDITY, owner);

        vm.prank(owner);
        smartLendingFactory.updateDeployer(deployer, true);
    }

    function test_deploy() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                FluidDexErrors.FluidSmartLendingFactoryError.selector,
                FluidDexTypes.SmartLendingFactory__ZeroAddress
            )
        );
        smartLendingFactory = new FluidSmartLendingFactory(address(0), LIQUIDITY, owner);

        vm.expectRevert(
            abi.encodeWithSelector(
                FluidDexErrors.FluidSmartLendingFactoryError.selector,
                FluidDexTypes.SmartLendingFactory__ZeroAddress
            )
        );
        smartLendingFactory = new FluidSmartLendingFactory(DEX_FACTORY, address(0), owner);

        vm.expectRevert(
            abi.encodeWithSelector(
                FluidDexErrors.FluidSmartLendingFactoryError.selector,
                FluidDexTypes.SmartLendingFactory__ZeroAddress
            )
        );
        smartLendingFactory = new FluidSmartLendingFactory(DEX_FACTORY, LIQUIDITY, address(0));

        smartLendingFactory = new FluidSmartLendingFactory(DEX_FACTORY, LIQUIDITY, owner);
    }

    function test_updateDeployer() public {
        assertTrue(smartLendingFactory.isDeployer(deployer));
        assertTrue(smartLendingFactory.isDeployer(owner));
        address newDeployer = makeAddr("newDeployer");
        assertFalse(smartLendingFactory.isDeployer(newDeployer));
        // Unauthorized access
        vm.prank(alice);
        vm.expectRevert("UNAUTHORIZED");
        smartLendingFactory.updateDeployer(newDeployer, true);
        // Authorized access
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit LogDeployerUpdated(newDeployer, true);
        smartLendingFactory.updateDeployer(newDeployer, true);
        assertTrue(smartLendingFactory.isDeployer(newDeployer));
        vm.prank(owner);
        smartLendingFactory.updateDeployer(newDeployer, false);
        assertFalse(smartLendingFactory.isDeployer(newDeployer));
    }

    function test_updateSmartLendingAuth() public {
        address newAuth = makeAddr("newAuth");
        assertTrue(smartLendingFactory.isSmartLendingAuth(address(smartLending), owner));
        assertFalse(smartLendingFactory.isSmartLendingAuth(address(smartLending), newAuth));
        // Unauthorized access
        vm.prank(alice);
        vm.expectRevert("UNAUTHORIZED");
        smartLendingFactory.updateSmartLendingAuth(address(smartLending), newAuth, true);
        // Authorized access
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit LogAuthUpdated(address(smartLending), newAuth, true);
        smartLendingFactory.updateSmartLendingAuth(address(smartLending), newAuth, true);
        assertTrue(smartLendingFactory.isSmartLendingAuth(address(smartLending), newAuth));
        assertFalse(smartLendingFactory.isSmartLendingAuth(alice, newAuth));
        vm.prank(owner);
        smartLendingFactory.updateSmartLendingAuth(address(smartLending), newAuth, false);
        assertFalse(smartLendingFactory.isSmartLendingAuth(address(smartLending), newAuth));
    }

    function test_setSmartLendingCreationCode() public {
        bytes memory creationCode = hex"60006000556000600055";
        // Unauthorized access
        vm.prank(alice);
        vm.expectRevert("UNAUTHORIZED");
        smartLendingFactory.setSmartLendingCreationCode(creationCode);
        // Authorized access
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit LogSetCreationCode(address(0x104fBc016F4bb334D775a19E8A6510109AC63E00));
        smartLendingFactory.setSmartLendingCreationCode(creationCode);
        assertEq(smartLendingFactory.smartLendingCreationCode(), creationCode);
    }

    function test_deploySmartLending() public {
        vm.prank(owner);
        smartLendingFactory.setSmartLendingCreationCode(type(FluidSmartLending).creationCode);

        uint256 dexId = 1;

        address expectedAddress = smartLendingFactory.getSmartLendingAddress(dexId);
        assertEq(expectedAddress, 0xe696CD58c51e8CEb6fA10cf546175dfB40496dc6);

        assertFalse(smartLendingFactory.isSmartLending(expectedAddress));

        // Unauthorized access
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                FluidDexErrors.FluidSmartLendingFactoryError.selector,
                FluidDexTypes.SmartLendingFactory__Unauthorized
            )
        );
        smartLendingFactory.deploy(dexId);

        assertFalse(smartLendingFactory.isSmartLending(expectedAddress));

        // Authorized access
        vm.prank(deployer);
        vm.expectEmit(true, true, true, true);
        emit LogSmartLendingDeployed(dexId, address(0xe696CD58c51e8CEb6fA10cf546175dfB40496dc6));
        address newSmartLending = smartLendingFactory.deploy(dexId);

        assertEq(newSmartLending, expectedAddress);

        assertTrue(smartLendingFactory.isSmartLendingAuth(newSmartLending, owner));

        assertTrue(smartLendingFactory.isSmartLending(newSmartLending));
    }

    function test_allTokens() public {
        vm.prank(owner);
        smartLendingFactory.setSmartLendingCreationCode(type(FluidSmartLending).creationCode);

        uint256 dexId = 1;

        vm.prank(deployer);
        address newSmartLending = smartLendingFactory.deploy(dexId);

        address[] memory allTokens = smartLendingFactory.allTokens();
        assertEq(allTokens.length, 1);
        assertEq(allTokens[0], newSmartLending);
    }
}
