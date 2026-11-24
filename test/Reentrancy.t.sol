// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VestingVault} from "../src/VestingVault.sol";

/// @dev Token that calls vault.release() again while the vault is paying the attacker.
contract ReentrantToken is ERC20 {
    VestingVault public vault;
    uint256 public targetId;
    address public attacker;
    bool public attempted;
    bool public reentrySucceeded;

    constructor() ERC20("Evil", "EVL") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function arm(VestingVault v, uint256 id, address who) external {
        vault = v;
        targetId = id;
        attacker = who;
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        if (to == attacker && !attempted) {
            attempted = true;
            try vault.release(targetId) {
                reentrySucceeded = true;
            } catch {}
        }
    }
}

contract ReentrancyTest is Test {
    ReentrantToken token;
    VestingVault vault;
    address alice = makeAddr("alice");

    function test_reentrantTokenCannotDrainVault() public {
        vm.warp(1000);
        token = new ReentrantToken();
        vault = new VestingVault(IERC20(address(token)));
        token.mint(address(vault), 1_000_000);
        uint256 id = vault.createSchedule(alice, 1_000_000, 1000, 0, 1000, false);
        token.arm(vault, id, alice);

        vm.warp(1500); // 50% vested
        vault.release(id);

        assertTrue(token.attempted(), "attack was attempted");
        assertFalse(token.reentrySucceeded(), "reentrant call must fail");
        assertEq(token.balanceOf(alice), 500_000, "paid exactly once");
        assertEq(vault.totalAllocated(), 500_000);
        assertEq(token.balanceOf(address(vault)), 500_000);
    }
}
