// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";
import {Quote} from "../src/Quote.sol";

/// @title Differential test — Quote.sol against an independent Python reference
/// @notice `trimmy/AGENTS.md`: "A test that exercises our own implementation on both sides proves
///         self-consistency and nothing else."
///
///         `Quote.sol` uses `Math.mulDiv` (512-bit intermediate) under checked 256-bit arithmetic.
///         `script/quote_reference.py` uses Python arbitrary-precision integers and a formula
///         re-derived from the FTSO definition rather than transcribed from the Solidity. They
///         share no code, no language and no overflow behaviour.
///
///         The fixture is deterministic (fixed seed) and committed, so this test is hermetic — it
///         needs no network and no Python at run time. `python3 script/quote_reference.py --check`
///         proves the committed fixture still matches a fresh generation.
contract QuoteDifferentialTest is Test {
    string internal constant FIXTURE = "test/fixtures/quote_vectors.json";

    function test_matchesPythonReference() public view {
        string memory json = vm.readFile(FIXTURE);

        uint256[] memory amountIn = vm.parseJsonUintArray(json, ".amountIn");
        uint256[] memory sellValue = vm.parseJsonUintArray(json, ".sellValue");
        int256[] memory sellDec = vm.parseJsonIntArray(json, ".sellDec");
        uint256[] memory sellTokenDec = vm.parseJsonUintArray(json, ".sellTokenDec");
        uint256[] memory buyValue = vm.parseJsonUintArray(json, ".buyValue");
        int256[] memory buyDec = vm.parseJsonIntArray(json, ".buyDec");
        uint256[] memory buyTokenDec = vm.parseJsonUintArray(json, ".buyTokenDec");
        uint256[] memory expected = vm.parseJsonUintArray(json, ".expected");

        uint256 n = amountIn.length;
        assertGt(n, 0, "fixture is empty");
        assertEq(sellValue.length, n);
        assertEq(sellDec.length, n);
        assertEq(sellTokenDec.length, n);
        assertEq(buyValue.length, n);
        assertEq(buyDec.length, n);
        assertEq(buyTokenDec.length, n);
        assertEq(expected.length, n);

        for (uint256 i = 0; i < n; i++) {
            uint256 got = Quote.convert(
                amountIn[i],
                Quote.Feed({
                    value: sellValue[i],
                    decimals: int8(sellDec[i]),
                    timestamp: uint64(block.timestamp)
                }),
                uint8(sellTokenDec[i]),
                Quote.Feed({
                    value: buyValue[i],
                    decimals: int8(buyDec[i]),
                    timestamp: uint64(block.timestamp)
                }),
                uint8(buyTokenDec[i])
            );

            assertEq(got, expected[i], string.concat("vector ", vm.toString(i), " disagrees"));
        }
    }
}
