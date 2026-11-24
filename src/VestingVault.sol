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
        uint256 total; // total tokens promised
        uint256 released; // tokens already paid out
        uint64 start; // unix time when vesting starts
        uint64 cliff; // seconds after `start` before ANY token vests
        uint64 duration; // seconds after `start` when 100% is vested
        uint64 revokedAt; // 0 while not revoked
        bool revocable;
        bool revoked;
    }

    IERC20 public immutable token;
    uint256 public scheduleCount; // ids start from 1
    uint256 public totalAllocated; // tokens promised to beneficiaries and not yet paid out
    mapping(uint256 => Schedule) public schedules;
    mapping(address => uint256[]) private _schedulesOf;

    event ScheduleCreated(
        uint256 indexed id,
        address indexed beneficiary,
        uint256 amount,
        uint64 start,
        uint64 cliff,
        uint64 duration,
        bool revocable
    );
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

    /// @notice Create a vesting schedule for a beneficiary (owner only).
    /// @dev The vault must already hold enough tokens that are not promised to anyone else.
    /// @param beneficiary Address that will receive the vested tokens.
    /// @param amount Total number of tokens to vest.
    /// @param start Unix time when vesting starts (may be in the past).
    /// @param cliff Seconds after `start` during which nothing is vested.
    /// @param duration Seconds after `start` when everything is vested (must be >= cliff).
    /// @param revocable Whether the owner may revoke the unvested part later.
    /// @return id The id of the new schedule (ids start from 1).
    function createSchedule(
        address beneficiary,
        uint256 amount,
        uint64 start,
        uint64 cliff,
        uint64 duration,
        bool revocable
    ) external onlyOwner returns (uint256 id) {
        require(beneficiary != address(0), "zero beneficiary");
        require(amount > 0, "zero amount");
        require(duration > 0, "zero duration");
        require(cliff <= duration, "cliff > duration");
        require(token.balanceOf(address(this)) >= totalAllocated + amount, "insufficient funds");

        id = ++scheduleCount;
        schedules[id] = Schedule({
            beneficiary: beneficiary,
            total: amount,
            released: 0,
            start: start,
            cliff: cliff,
            duration: duration,
            revokedAt: 0,
            revocable: revocable,
            revoked: false
        });
        _schedulesOf[beneficiary].push(id);
        totalAllocated += amount;
        emit ScheduleCreated(id, beneficiary, amount, start, cliff, duration, revocable);
    }

    /// @dev Vesting formula. For a revoked schedule time is frozen at `revokedAt`.
    ///      Multiplication goes before division to keep precision; the result rounds down.
    function _vested(Schedule storage s) internal view returns (uint256) {
        uint256 t = s.revoked ? s.revokedAt : block.timestamp;
        uint256 start = s.start;
        if (t < start + s.cliff) return 0;
        if (t >= start + s.duration) return s.total;
        return (s.total * (t - start)) / s.duration;
    }

    /// @notice Amount of tokens vested so far (released or not) for a schedule.
    /// @param id Schedule id. Reverts if unknown.
    /// @return Vested amount according to the cliff + linear formula.
    function vestedAmount(uint256 id) public view returns (uint256) {
        Schedule storage s = schedules[id];
        require(s.beneficiary != address(0), "unknown id");
        return _vested(s);
    }

    /// @notice Amount that can be released right now (vested minus already released).
    /// @param id Schedule id. Reverts if unknown.
    /// @return Tokens currently claimable.
    function releasable(uint256 id) public view returns (uint256) {
        return vestedAmount(id) - schedules[id].released;
    }

    /// @notice Send all currently releasable tokens to the beneficiary. Anyone may call it.
    /// @dev Checks-Effects-Interactions: state is updated before the token transfer.
    /// @param id Schedule id. Reverts if unknown or if nothing can be released.
    function release(uint256 id) external nonReentrant {
        Schedule storage s = schedules[id];
        require(s.beneficiary != address(0), "unknown id");
        uint256 amount = _vested(s) - s.released;
        require(amount > 0, "nothing to release");

        // Effects
        s.released += amount;
        totalAllocated -= amount;

        // Interactions
        token.safeTransfer(s.beneficiary, amount);
        emit Released(id, s.beneficiary, amount);
    }

    /// @notice Revoke a schedule (owner only): the unvested part returns to the owner,
    ///         the vested part stays claimable by the beneficiary. Vesting is frozen.
    /// @param id Schedule id. Must be revocable and not yet revoked.
    function revoke(uint256 id) external nonReentrant onlyOwner {
        Schedule storage s = schedules[id];
        require(s.beneficiary != address(0), "unknown id");
        require(s.revocable, "not revocable");
        require(!s.revoked, "already revoked");

        uint256 unvested = s.total - _vested(s);

        // Effects
        s.revoked = true;
        s.revokedAt = uint64(block.timestamp);
        totalAllocated -= unvested;

        // Interactions
        if (unvested > 0) token.safeTransfer(owner(), unvested);
        emit Revoked(id, unvested);
    }

    /// @notice Withdraw tokens that are not promised to any schedule (owner only).
    /// @param to Recipient of the unallocated tokens.
    /// @return amount Number of tokens sent. Reverts if there is nothing to withdraw.
    function withdrawUnallocated(address to) external nonReentrant onlyOwner returns (uint256 amount) {
        require(to != address(0), "zero address");
        uint256 bal = token.balanceOf(address(this));
        require(bal > totalAllocated, "nothing to withdraw");
        amount = bal - totalAllocated;
        token.safeTransfer(to, amount);
    }

    /// @notice Ids of the schedules currently owned by an address.
    /// @param beneficiary The address to look up.
    /// @return List of schedule ids.
    function schedulesOf(address beneficiary) external view returns (uint256[] memory) {
        return _schedulesOf[beneficiary];
    }

    /// @notice Hand a schedule over to another address (current beneficiary only).
    /// @dev Already released amount stays recorded in the schedule.
    /// @param id Schedule id.
    /// @param newBeneficiary New owner of the schedule (must not be the zero address).
    function transferSchedule(uint256 id, address newBeneficiary) external {
        Schedule storage s = schedules[id];
        require(msg.sender == s.beneficiary, "not beneficiary");
        require(newBeneficiary != address(0), "zero address");

        uint256[] storage list = _schedulesOf[msg.sender];
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == id) {
                list[i] = list[list.length - 1];
                list.pop();
                break;
            }
        }
        s.beneficiary = newBeneficiary;
        _schedulesOf[newBeneficiary].push(id);
        emit ScheduleTransferred(id, msg.sender, newBeneficiary);
    }
}
