// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VestingVault} from "../src/VestingVault.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock", "MCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract VestingVaultTest is Test {
    VestingVault vault;
    MockToken token;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    uint64 start;

    // this test contract deploys the vault, so it is the owner

    function setUp() public {
        vm.warp(1000);
        token = new MockToken();
        vault = new VestingVault(IERC20(address(token)));
        token.mint(address(vault), 1_000_000);
        start = uint64(block.timestamp);
    }

    // total = 1_000_000, cliff = 200, duration = 1000 (example from the task)
    function _create(bool revocable) internal returns (uint256) {
        return vault.createSchedule(alice, 1_000_000, start, 200, 1000, revocable);
    }

    // ---------- formula ----------

    function test_vestedValuesFromTask() public {
        uint256 id = _create(true);
        vm.warp(start - 10);
        assertEq(vault.vestedAmount(id), 0, "before start");
        vm.warp(start + 199);
        assertEq(vault.vestedAmount(id), 0, "inside cliff");
        vm.warp(start + 200);
        assertEq(vault.vestedAmount(id), 200_000, "cliff boundary");
        vm.warp(start + 500);
        assertEq(vault.vestedAmount(id), 500_000, "middle");
        vm.warp(start + 777);
        assertEq(vault.vestedAmount(id), 777_000, "linear");
        vm.warp(start + 1000);
        assertEq(vault.vestedAmount(id), 1_000_000, "end");
        vm.warp(start + 5000);
        assertEq(vault.vestedAmount(id), 1_000_000, "after end");
    }

    function test_roundsDown() public {
        uint256 id = vault.createSchedule(bob, 1000, start, 0, 3, false);
        vm.warp(start + 1);
        assertEq(vault.vestedAmount(id), 333);
        vm.warp(start + 2);
        assertEq(vault.vestedAmount(id), 666);
        vm.warp(start + 3);
        assertEq(vault.vestedAmount(id), 1000);
    }

    function test_unknownIdReverts() public {
        vm.expectRevert();
        vault.vestedAmount(42);
    }

    // ---------- create ----------

    function test_createValidations() public {
        vm.expectRevert();
        vault.createSchedule(address(0), 1, start, 0, 10, false);
        vm.expectRevert();
        vault.createSchedule(bob, 0, start, 0, 10, false);
        vm.expectRevert();
        vault.createSchedule(bob, 1, start, 0, 0, false);
        vm.expectRevert();
        vault.createSchedule(bob, 1, start, 11, 10, false);
    }

    function test_cliffEqualDurationAllowed() public {
        uint256 id = vault.createSchedule(bob, 1000, start, 100, 100, false);
        vm.warp(start + 99);
        assertEq(vault.vestedAmount(id), 0);
        vm.warp(start + 100);
        assertEq(vault.vestedAmount(id), 1000);
    }

    function test_cannotPromiseMoreThanBalance() public {
        _create(true); // promises everything the vault holds
        vm.expectRevert();
        vault.createSchedule(bob, 1, start, 0, 10, false);
    }

    function test_strangerCannotCreate() public {
        vm.prank(bob);
        vm.expectRevert();
        vault.createSchedule(bob, 1, start, 0, 10, false);
    }

    // ---------- release ----------

    function test_multipleReleasesSumToTotal() public {
        uint256 id = _create(false);
        vm.warp(start + 300);
        vault.release(id);
        assertEq(token.balanceOf(alice), 300_000);
        vm.warp(start + 700);
        vault.release(id);
        assertEq(token.balanceOf(alice), 700_000);
        vm.warp(start + 5000);
        vault.release(id);
        assertEq(token.balanceOf(alice), 1_000_000);
        assertEq(vault.totalAllocated(), 0);
    }

    function test_releaseGoesToBeneficiaryNotCaller() public {
        uint256 id = _create(false);
        vm.warp(start + 500);
        vm.prank(bob); // a stranger triggers the payout
        vault.release(id);
        assertEq(token.balanceOf(alice), 500_000);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_releaseNothingReverts() public {
        uint256 id = _create(false);
        vm.warp(start + 100); // still inside cliff
        vm.expectRevert();
        vault.release(id);
    }

    // ---------- revoke ----------

    function test_revokeBeforeCliff() public {
        uint256 id = _create(true);
        vm.warp(start + 100);
        vault.revoke(id);
        assertEq(token.balanceOf(address(this)), 1_000_000, "owner got everything back");
        assertEq(vault.totalAllocated(), 0);
        vm.warp(start + 5000);
        vm.expectRevert();
        vault.release(id);
    }

    function test_revokeInMiddleFreezesVesting() public {
        uint256 id = _create(true);
        vm.warp(start + 400);
        vault.revoke(id);
        assertEq(token.balanceOf(address(this)), 600_000, "unvested part returned");
        assertEq(vault.totalAllocated(), 400_000);
        vm.warp(start + 10 * 365 days);
        vault.release(id);
        assertEq(token.balanceOf(alice), 400_000, "only what was vested at revoke");
        assertEq(vault.totalAllocated(), 0);
    }

    function test_revokeAfterEndReturnsZero() public {
        uint256 id = _create(true);
        vm.warp(start + 2000);
        vault.revoke(id);
        assertEq(token.balanceOf(address(this)), 0);
        vault.release(id);
        assertEq(token.balanceOf(alice), 1_000_000);
    }

    function test_nonRevocableCannotBeRevoked() public {
        uint256 id = _create(false);
        vm.expectRevert();
        vault.revoke(id);
    }

    function test_cannotRevokeTwice() public {
        uint256 id = _create(true);
        vault.revoke(id);
        vm.expectRevert();
        vault.revoke(id);
    }

    function test_strangerCannotRevoke() public {
        uint256 id = _create(true);
        vm.prank(bob);
        vm.expectRevert();
        vault.revoke(id);
    }

    // ---------- housekeeping ----------

    function test_withdrawUnallocatedKeepsPromisedTokens() public {
        vault.createSchedule(alice, 600_000, start, 0, 1000, false);
        vault.withdrawUnallocated(bob);
        assertEq(token.balanceOf(bob), 400_000);
        assertEq(token.balanceOf(address(vault)), 600_000);
        vm.expectRevert(); // nothing left to withdraw
        vault.withdrawUnallocated(bob);
    }

    function test_strangerCannotWithdrawUnallocated() public {
        vm.prank(bob);
        vm.expectRevert();
        vault.withdrawUnallocated(bob);
    }

    // ---------- bonus: transferSchedule ----------

    function test_transferSchedule() public {
        uint256 id = _create(false);
        vm.warp(start + 500);
        vault.release(id); // alice already received 500_000

        vm.prank(alice);
        vault.transferSchedule(id, bob);

        assertEq(vault.schedulesOf(alice).length, 0);
        assertEq(vault.schedulesOf(bob).length, 1);
        assertEq(vault.schedulesOf(bob)[0], id);

        vm.warp(start + 5000);
        vault.release(id);
        assertEq(token.balanceOf(bob), 500_000, "only the rest goes to the new owner");
    }

    function test_strangerCannotTransferSchedule() public {
        uint256 id = _create(false);
        vm.prank(bob);
        vm.expectRevert();
        vault.transferSchedule(id, bob);
    }

    // ---------- fuzz ----------

    function testFuzz_vestedBoundedAndMonotonic(uint96 total, uint32 cliff, uint32 dur, uint32 t1, uint32 t2) public {
        uint256 tot = bound(uint256(total), 1, 1e24);
        uint256 d = bound(uint256(dur), 1, type(uint32).max);
        uint256 c = bound(uint256(cliff), 0, d);
        token.mint(address(vault), tot);
        uint256 id = vault.createSchedule(bob, tot, start, uint64(c), uint64(d), false);

        uint256 a = t1 <= t2 ? t1 : t2;
        uint256 b = t1 <= t2 ? t2 : t1;
        vm.warp(uint256(start) + a);
        uint256 v1 = vault.vestedAmount(id);
        vm.warp(uint256(start) + b);
        uint256 v2 = vault.vestedAmount(id);

        assertLe(v2, tot, "never above total");
        assertGe(v2, v1, "never decreases");
    }
}
