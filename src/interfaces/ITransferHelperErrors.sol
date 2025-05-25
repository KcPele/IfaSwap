// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITransferHelperErrors {
    error TransferFromFailed(); // Replaces "STF"
    error TransferFailed();     // Replaces "ST"
    error ApproveFailed();      // Replaces "SA"
    error ETHTransferFailed();  // Replaces "STE"
}
