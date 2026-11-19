// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title VestingVault — token vesting with cliff, linear unlock and revocation (STUDENT STARTER)
/// @notice One vault holds tokens for many beneficiaries. The owner (e.g. the project team)
///         creates schedules; beneficiaries (team, investors, advisors) receive tokens over time.
contract VestingVault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============================================================
    //  PROVIDED PART (identical to the student starter file)
    // ============================================================
    struct Schedule {
        address beneficiary;
        uint256 total;      // total tokens promised
        uint256 released;   // tokens already paid out
        uint64 start;       // unix time when vesting starts
        uint64 cliff;       // seconds after `start` before ANY token vests
        uint64 duration;    // seconds after `start` when 100% is vested
        uint64 revokedAt;   // 0 while not revoked
        bool revocable;
        bool revoked;
    }

    IERC20 public immutable token;
    uint256 public scheduleCount;                       // ids start from 1
    uint256 public totalAllocated;                      // tokens promised to beneficiaries and not yet paid out
    mapping(uint256 => Schedule) public schedules;
    mapping(address => uint256[]) private _schedulesOf;

    event ScheduleCreated(uint256 indexed id, address indexed beneficiary, uint256 amount, uint64 start, uint64 cliff, uint64 duration, bool revocable);
    event Released(uint256 indexed id, address indexed beneficiary, uint256 amount);
    event Revoked(uint256 indexed id, uint256 returnedToOwner);
    event ScheduleTransferred(uint256 indexed id, address indexed from, address indexed to);

    constructor(IERC20 token_) Ownable(msg.sender) {
        require(address(token_) != address(0), "zero token");
        token = token_;
    }

    // ============================================================
    //  YOUR CODE STARTS HERE
    // ============================================================

    // ------------------------------------------------------------
    // STEP 1 — create a schedule (owner only)
    // Validate: beneficiary != 0, amount > 0, duration > 0, cliff <= duration,
    //   and the vault must hold enough NOT-YET-PROMISED tokens:
    //   token.balanceOf(address(this)) - totalAllocated >= amount
    // Then: id = ++scheduleCount, store the Schedule (released = 0, revokedAt = 0, revoked = false),
    //   remember the id in _schedulesOf[beneficiary], totalAllocated += amount,
    //   emit ScheduleCreated. Return the id.
    // ------------------------------------------------------------
    function createSchedule(
        address beneficiary,
        uint256 amount,
        uint64 start,
        uint64 cliff,
        uint64 duration,
        bool revocable
    ) external onlyOwner returns (uint256 id) {
        revert("TODO step 1");
    }

    // ------------------------------------------------------------
    // STEP 2 — the vesting formula
    // Let t = block.timestamp, but if the schedule was revoked use s.revokedAt instead.
    //   t <  start + cliff       -> 0
    //   t >= start + duration    -> total
    //   otherwise                -> total * (t - start) / duration     (integer division, rounds down)
    // vestedAmount(id) reverts for an unknown id. releasable(id) = vestedAmount(id) - released.
    // ------------------------------------------------------------
    function vestedAmount(uint256 id) public view returns (uint256) {
        revert("TODO step 2");
    }

    function releasable(uint256 id) public view returns (uint256) {
        revert("TODO step 2");
    }

    // ------------------------------------------------------------
    // STEP 3 — release (ANYONE may call it, tokens always go to the beneficiary)
    // Reverts if the id is unknown or there is nothing to release.
    // Order matters: update state FIRST (released, totalAllocated), send tokens LAST.
    // Use SafeERC20 (token.safeTransfer). Emit Released.
    // ------------------------------------------------------------
    function release(uint256 id) external {
        revert("TODO step 3");
    }

    // ------------------------------------------------------------
    // STEP 4 — revoke (owner only)
    // Only for revocable, not yet revoked schedules.
    // The UNVESTED part (total - vested now) goes back to the owner immediately.
    // The already vested part stays claimable by the beneficiary via release().
    // After revoking, vesting is frozen: set revoked = true, revokedAt = now.
    // totalAllocated must drop by the returned amount. Emit Revoked.
    // ------------------------------------------------------------
    function revoke(uint256 id) external {
        revert("TODO step 4");
    }

    // ------------------------------------------------------------
    // STEP 5 — housekeeping
    // withdrawUnallocated(to): owner only; sends balance - totalAllocated to `to`
    //   (rescues tokens sent by mistake / returned by nobody). Reverts if the amount is 0.
    // schedulesOf(beneficiary): ids of schedules currently owned by the address.
    // ------------------------------------------------------------
    function withdrawUnallocated(address to) external returns (uint256 amount) {
        revert("TODO step 5");
    }

    function schedulesOf(address beneficiary) external view returns (uint256[] memory) {
        revert("TODO step 5");
    }

    // ------------------------------------------------------------
    // BONUS — a beneficiary can hand the schedule to another address
    // Only the CURRENT beneficiary. New beneficiary != 0. Already released amount stays recorded.
    // schedulesOf must reflect the change (old owner no longer lists it, new owner does).
    // Emit ScheduleTransferred.
    // ------------------------------------------------------------
    function transferSchedule(uint256 id, address newBeneficiary) external {
        revert("TODO bonus");
    }
}
