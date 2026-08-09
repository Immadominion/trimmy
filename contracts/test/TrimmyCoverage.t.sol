// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {TrimmyFixture} from "./TrimmyInvariant.t.sol";

/// @title Handler coverage
/// @notice Proves the invariant handler can actually reach `execute`. Without this, the invariant
///         suite could report every invariant green while nothing ever happened — an earlier
///         version of it did exactly that: 6,586 `arm` calls, 0 reverts reported, 0 rules created,
///         because `try/catch` swallowed every revert. `proceedsFullyAccounted` in particular would
///         have passed trivially as 0 == 0.
///
/// @dev This lives here rather than in `afterInvariant` because coverage is not an invariant. It
///      does not hold for a short call sequence, so the shrinker collapses any failure to a trivial
///      one-call case and masks the real problem.
contract TrimmyCoverageTest is TrimmyFixture {
    function testFuzz_armAlwaysSucceeds(uint256 a, uint256 b, uint256 c, uint8 d) public {
        vm.prank(address(0x9D9));
        handler.armRule(a, b, c, d);
        assertGt(handler.ruleCount(), 0, "handler cannot arm");
    }

    function testFuzz_armThenExecuteAlwaysSucceeds(uint256 a, uint256 b, uint8 d) public {
        vm.prank(address(0x9D9));
        handler.armRule(a, b, 1e6, d);
        vm.prank(address(0x9D9));
        handler.executeRule(0);
        assertGt(handler.ghostExecutions(), 0, "handler cannot execute");
        assertGt(handler.ghostToUser(), 0, "execution paid the user nothing");
    }
}
