// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;


contract NoOpTellor {
    // --- Mock data reporting functions ---

    function getTimestampbyRequestIDandIndex(uint, uint) external pure returns (uint) {
        return 0;
    }

    function getNewValueCountbyRequestId(uint) external pure returns (uint) {
        return 1;
    }

    function retrieveData(uint256, uint256) external pure returns (uint256) {
        return 0;
    }
}
