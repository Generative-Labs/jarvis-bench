// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {ConstantProductAMM} from "../src/ConstantProductAMM.sol";
import {AMMFactory} from "../src/AMMFactory.sol";
import {MockToken} from "./mocks/MockToken.sol";

contract ConstantProductAMMTest is Test {
    ConstantProductAMM public amm;
    AMMFactory public factory;
    MockToken public tokenA;
    MockToken public tokenB;
    
    address public user1 = makeAddr("user1");
    
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 1e18;

    function setUp() public {
        factory = new AMMFactory();
        tokenA = new MockToken("Token A", "TKNA", 18, INITIAL_SUPPLY);
        tokenB = new MockToken("Token B", "TKNB", 18, INITIAL_SUPPLY);
        
        address pairAddress = factory.createPair(address(tokenA), address(tokenB));
        amm = ConstantProductAMM(pairAddress);
        
        tokenA.transfer(user1, 50_000 * 1e18);
        tokenB.transfer(user1, 50_000 * 1e18);
    }

    function testFactoryCreatePair() public {
        assertEq(factory.allPairsLength(), 1);
        assertEq(factory.getPair(address(tokenA), address(tokenB)), address(amm));
        assertEq(factory.getPair(address(tokenB), address(tokenA)), address(amm));
    }

    function testGetAmountOut() public {
        uint256 amountIn = 1_000 * 1e18;
        uint256 reserveIn = 100_000 * 1e18;
        uint256 reserveOut = 100_000 * 1e18;
        
        uint256 amountOut = amm.getAmountOut(amountIn, reserveIn, reserveOut);
        
        // Expected calculation with 0.3% fee
        uint256 expected = (amountIn * 9970 * reserveOut) / (reserveIn * 10000 + amountIn * 9970);
        assertEq(amountOut, expected);
    }

    function testRevertInvalidToken() public {
        address invalidToken = makeAddr("invalidToken");
        
        vm.expectRevert(ConstantProductAMM.InvalidToken.selector);
        amm.getAmountOut(1000, 0, 0);
    }
}
