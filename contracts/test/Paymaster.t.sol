// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {EntryPoint, IEntryPoint, PackedUserOperation, UserOperationLib} from "account-abstraction/core/EntryPoint.sol";
import {Vm} from "forge-std/Vm.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";
import {Ownable} from "solady/auth/Ownable.sol";

import {BaseTest} from "./BaseTest.t.sol";
import {MockAccount} from "./mocks/MockAccount.sol";
import {MockEndpoint} from "./mocks/MockEndpoint.sol";
import {Paymaster} from "../src/Paymaster.sol";
import {MockPaymaster} from "./mocks/MockPaymaster.sol";
import {MockUserOpPrecheck} from "./mocks/MockUserOpPrecheck.sol";

contract PaymasterTest is BaseTest, MockEndpoint {
    using UserOperationLib for PackedUserOperation;
    using ECDSA for bytes32;

    IEntryPoint entryPoint;
    MockAccount mockAccount;
    MockPaymaster paymaster;
    address precheckAddress;

    Vm.Wallet signer = vm.createWallet(block.timestamp);
    Vm.Wallet otherSigner = vm.createWallet(1000);

    event ClaimAddressSet(address indexed fulfiller, address indexed claimAddress);

    function setUp() external {
        entryPoint = IEntryPoint(new EntryPoint());
        mockAccount = new MockAccount();

        paymaster = new MockPaymaster(address(entryPoint));
        approveAddr = address(paymaster);
        precheckAddress = address(new MockUserOpPrecheck());

        _setUp();
    }

    modifier fundPaymaster(address account, uint256 amount) {
        vm.prank(account);
        (bool success,) = payable(paymaster).call{value: amount}("");
        assertTrue(success);
        _;
    }

    function test_deployment_reverts_zeroAddressEntryPoint() external {
        vm.expectRevert(Paymaster.ZeroAddress.selector);
        new MockPaymaster(address(0));
    }

    function test_receive_incrementsMagicSpendBalance(uint256 amount) external fundAccount(signer.addr, amount) {
        uint256 initialBalance = paymaster.getMagicSpendBalance(signer.addr);

        vm.prank(signer.addr);
        (bool success,) = payable(paymaster).call{value: amount}("");
        assertTrue(success);

        assertEq(paymaster.getMagicSpendBalance(signer.addr), initialBalance + amount);
    }

    function test_entryPointDeposit_incrementsMagicSpendBalance(uint256 amount)
        external
        fundAccount(signer.addr, amount)
    {
        uint256 initialBalance = paymaster.getMagicSpendBalance(signer.addr);

        vm.prank(signer.addr);
        paymaster.entryPointDeposit{value: amount}(0);

        assertEq(paymaster.getMagicSpendBalance(signer.addr), initialBalance + amount);
    }

    function test_entryPointDeposit_revertsIfInsufficientBalance(uint256 amount) external {
        vm.assume(amount > 0);

        vm.expectRevert(
            abi.encodeWithSelector(Paymaster.InsufficientMagicSpendBalance.selector, signer.addr, 0, amount)
        );
        vm.prank(signer.addr);
        paymaster.entryPointDeposit(amount);
    }

    function test_entryPointDeposit_decrementsMagicSpendBalance(uint256 amount)
        external
        fundAccount(signer.addr, amount)
        fundPaymaster(signer.addr, amount)
    {
        uint256 initialBalance = paymaster.getMagicSpendBalance(signer.addr);

        vm.prank(signer.addr);
        paymaster.entryPointDeposit(amount);

        assertEq(paymaster.getMagicSpendBalance(signer.addr), initialBalance - amount);
    }

    function test_entryPointDeposit_incrementsGasBalance(uint256 amount)
        external
        fundAccount(signer.addr, amount)
        fundPaymaster(signer.addr, amount)
    {
        uint256 initialBalance = paymaster.getGasBalance(signer.addr);

        vm.prank(signer.addr);
        paymaster.entryPointDeposit(amount);

        assertEq(paymaster.getGasBalance(signer.addr), initialBalance + amount);
    }

    function test_entryPointDeposit_routesToEntryPoint(uint256 amount) public fundAccount(signer.addr, amount) {
        uint256 initialBalance = address(entryPoint).balance;

        vm.prank(signer.addr);
        paymaster.entryPointDeposit{value: amount}(amount);

        assertEq(address(entryPoint).balance, initialBalance + amount);
    }

    function test_entryPointDeposit_storesBalanceInEntryPointOnBehalfOfPaymaster(uint256 amount)
        public
        fundAccount(signer.addr, amount)
    {
        uint256 initialBalance = entryPoint.balanceOf(address(paymaster));

        vm.prank(signer.addr);
        paymaster.entryPointDeposit{value: amount}(amount);

        assertEq(entryPoint.balanceOf(address(paymaster)), initialBalance + amount);
    }

    function test_withdrawTo_revertsIfWithdrawAddressIsZeroAddress() public {
        vm.prank(signer.addr);
        vm.expectRevert(Paymaster.ZeroAddress.selector);
        paymaster.withdrawTo(payable(address(0)), 1);
    }

    function test_withdrawTo_revertsIfInsufficientBalance(address payable withdrawAddress, uint256 amount) public {
        vm.assume(amount > 0);
        _isValidWithdrawAddress(withdrawAddress);

        vm.prank(signer.addr);
        vm.expectRevert(
            abi.encodeWithSelector(Paymaster.InsufficientMagicSpendBalance.selector, signer.addr, 0, amount)
        );
        paymaster.withdrawTo(withdrawAddress, amount);
    }

    function test_withdrawTo_decrementsMagicSpendBalance(address payable withdrawAddress, uint256 amount)
        external
        fundAccount(signer.addr, amount)
        fundPaymaster(signer.addr, amount)
    {
        vm.assume(amount > 0);
        _isValidWithdrawAddress(withdrawAddress);

        uint256 initialBalance = paymaster.getMagicSpendBalance(signer.addr);

        vm.prank(signer.addr);
        paymaster.withdrawTo(withdrawAddress, amount);

        assertEq(paymaster.getMagicSpendBalance(signer.addr), initialBalance - amount);
    }

    function test_withdrawTo_withdrawsFromPaymaster(address payable withdrawAddress, uint256 amount)
        public
        fundAccount(signer.addr, amount)
        fundPaymaster(signer.addr, amount)
    {
        vm.assume(amount > 0);
        _isValidWithdrawAddress(withdrawAddress);

        uint256 initialBalance = address(paymaster).balance;

        vm.prank(signer.addr);
        paymaster.withdrawTo(withdrawAddress, amount);

        assertEq(address(paymaster).balance, initialBalance - amount);
    }

    function test_withdrawTo_sendsFundsToWithdrawAddress(address payable withdrawAddress, uint256 amount)
        public
        fundAccount(signer.addr, amount)
        fundPaymaster(signer.addr, amount)
    {
        vm.assume(amount > 0);
        _isValidWithdrawAddress(withdrawAddress);

        uint256 initialBalance = withdrawAddress.balance;

        vm.prank(signer.addr);
        paymaster.withdrawTo(withdrawAddress, amount);

        assertEq(withdrawAddress.balance, initialBalance + amount);
    }

    function test_entryPointWithdrawTo_revertsIfWithdrawAddressIsZeroAddress() public {
        vm.prank(signer.addr);
        vm.expectRevert(Paymaster.ZeroAddress.selector);
        paymaster.entryPointWithdrawTo(payable(address(0)), 1);
    }

    function test_entryPointWithdrawTo_revertsIfInsufficientBalance(address payable withdrawAddress, uint256 amount)
        public
    {
        vm.assume(amount > 0);
        _isValidWithdrawAddress(withdrawAddress);

        vm.prank(signer.addr);
        vm.expectRevert(abi.encodeWithSelector(Paymaster.InsufficientGasBalance.selector, signer.addr, 0, amount));
        paymaster.entryPointWithdrawTo(withdrawAddress, amount);
    }

    function test_entryPointWithdrawTo_decrementsGasBalance(address payable withdrawAddress, uint256 amount)
        external
        fundAccount(signer.addr, amount)
        fundPaymaster(signer.addr, amount)
    {
        vm.assume(amount > 0);
        _isValidWithdrawAddress(withdrawAddress);

        _deposit(amount);

        uint256 initialBalance = paymaster.getGasBalance(signer.addr);

        vm.prank(signer.addr);
        paymaster.entryPointWithdrawTo(withdrawAddress, amount);

        assertEq(paymaster.getGasBalance(signer.addr), initialBalance - amount);
    }

    function test_entryPointWithdrawTo_decrementsTotalTrackedGasBalance(address payable withdrawAddress, uint256 amount)
        external
        fundAccount(signer.addr, amount)
        fundPaymaster(signer.addr, amount)
    {
        vm.assume(amount > 0);
        _isValidWithdrawAddress(withdrawAddress);

        _deposit(amount);

        uint256 initialBalance = paymaster.totalTrackedGasBalance();

        vm.prank(signer.addr);
        paymaster.entryPointWithdrawTo(withdrawAddress, amount);

        assertEq(paymaster.totalTrackedGasBalance(), initialBalance - amount);
    }

    function test_entryPointWithdrawTo_withdrawsFromEntryPoint(address payable withdrawAddress, uint256 amount)
        public
        fundAccount(signer.addr, amount)
        fundPaymaster(signer.addr, amount)
    {
        vm.assume(amount > 0);
        _isValidWithdrawAddress(withdrawAddress);

        _deposit(amount);

        uint256 initialBalance = address(entryPoint).balance;

        vm.prank(signer.addr);
        paymaster.entryPointWithdrawTo(withdrawAddress, amount);

        assertEq(address(entryPoint).balance, initialBalance - amount);
    }

    function test_entryPointWithdrawTo_sendsFundsToWithdrawAddress(address payable withdrawAddress, uint256 amount)
        public
        fundAccount(signer.addr, amount)
        fundPaymaster(signer.addr, amount)
    {
        vm.assume(amount > 0);
        _isValidWithdrawAddress(withdrawAddress);

        _deposit(amount);

        uint256 initialBalance = withdrawAddress.balance;

        vm.prank(signer.addr);
        paymaster.entryPointWithdrawTo(withdrawAddress, amount);

        assertEq(withdrawAddress.balance, initialBalance + amount);
    }

    function test_setClaimAddress_setsClaimAddress(address newClaimAddress) public {
        address startClaimAddress = paymaster.fulfillerClaimAddress(signer.addr);

        vm.prank(signer.addr);
        paymaster.setClaimAddress(newClaimAddress);

        assertEq(startClaimAddress, address(0));
        assertEq(paymaster.fulfillerClaimAddress(signer.addr), newClaimAddress);
    }

    function test_setClaimAddress_emitsClaimAddressSetEvent() public {
        address newClaimAddress = address(0x123);

        vm.expectEmit(true, true, true, false);
        emit ClaimAddressSet(signer.addr, newClaimAddress);

        vm.prank(signer.addr);
        paymaster.setClaimAddress(newClaimAddress);
    }

    function test_validatePaymasterUserOp_revertsIfNotCalledByEntryPoint(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) public {
        vm.expectRevert(Paymaster.NotEntryPoint.selector);
        paymaster.validatePaymasterUserOp(userOp, userOpHash, maxCost);
    }

    function test_validatePaymasterUserOp_revertsIfFulfillerDoesNotHaveEnoughMagicSpendBalance(uint256 amount)
        public
        fundAccount(signer.addr, amount)
        fundPaymaster(signer.addr, amount)
    {
        PackedUserOperation[] memory userOps = _generateUserOps(signer.privateKey, amount, address(0), 0);
        uint256 maxCost = this.calculateMaxCost(userOps[0]);

        _deposit(amount);

        vm.assume(maxCost <= amount && amount <= type(uint256).max - maxCost);

        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOpWithRevert.selector,
                0,
                "AA33 reverted",
                abi.encodeWithSelector(Paymaster.InsufficientMagicSpendBalance.selector, signer.addr, 0, amount)
            )
        );
        entryPoint.handleOps(userOps, payable(BUNDLER));
    }

    function test_validatePaymasterUserOp_revertsIfFulfillerHasInsufficientGasBalance(uint256 amount)
        public
        fundAccount(signer.addr, amount)
        fundPaymaster(signer.addr, amount)
    {
        PackedUserOperation[] memory userOps = _generateUserOps(otherSigner.privateKey, amount, address(0), 0);
        uint256 maxCost = this.calculateMaxCost(userOps[0]);

        vm.assume(maxCost <= amount && amount <= type(uint256).max - maxCost);

        _deposit(maxCost);

        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOpWithRevert.selector,
                0,
                "AA33 reverted",
                abi.encodeWithSelector(Paymaster.InsufficientGasBalance.selector, otherSigner.addr, 0, maxCost)
            )
        );
        entryPoint.handleOps(userOps, payable(BUNDLER));
    }

    function test_validatePaymasterUserOp_revertsIfFulfillerHasInsufficientGasBalanceOnSecondTry(
        uint256 amount,
        uint256 ethAmount
    ) public fundAccount(signer.addr, amount) fundPaymaster(signer.addr, amount) {
        PackedUserOperation[] memory userOps = _generateUserOps(signer.privateKey, ethAmount, address(0), 0);
        uint256 maxCost = this.calculateMaxCost(userOps[0]);

        vm.assume(ethAmount < type(uint256).max - maxCost * 2 && ethAmount + maxCost * 2 < amount);
        _deposit(maxCost);

        entryPoint.handleOps(userOps, payable(BUNDLER));

        userOps = _generateUserOps(otherSigner.privateKey, ethAmount, address(0), 1);
        maxCost = this.calculateMaxCost(userOps[0]);
        _deposit(maxCost);

        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOpWithRevert.selector,
                0,
                "AA33 reverted",
                abi.encodeWithSelector(Paymaster.InsufficientGasBalance.selector, otherSigner.addr, 0, maxCost)
            )
        );
        entryPoint.handleOps(userOps, payable(BUNDLER));
    }

    function test_validatePaymasterUserOp_incrementsWithdrawableBalance(uint256 amount, uint256 ethAmount)
        public
        fundAccount(signer.addr, amount)
        fundPaymaster(signer.addr, amount)
    {
        assertEq(paymaster.getGasBalance(signer.addr), address(entryPoint).balance);
        PackedUserOperation[] memory userOps = _generateUserOps(signer.privateKey, ethAmount, address(0), 0);
        uint256 maxCost = this.calculateMaxCost(userOps[0]);

        vm.assume(ethAmount < type(uint256).max - maxCost && ethAmount + maxCost < amount);
        _deposit(maxCost);

        entryPoint.handleOps(userOps, payable(BUNDLER));

        assertEq(paymaster.getGasBalance(signer.addr), address(entryPoint).balance);
    }

    function test_validatePaymasterUserOp_revertsIfPrecheckFails(uint256 amount, uint256 ethAmount)
        public
        fundAccount(signer.addr, amount)
        fundPaymaster(signer.addr, amount)
    {
        vm.assume(ethAmount > 0);

        PackedUserOperation[] memory userOps = _generateUserOps(signer.privateKey, ethAmount, precheckAddress, 0);
        uint256 maxCost = this.calculateMaxCost(userOps[0]);

        vm.assume(ethAmount < type(uint256).max - maxCost && ethAmount + maxCost < amount);
        _deposit(maxCost);

        vm.expectRevert(abi.encodeWithSelector(IEntryPoint.FailedOpWithRevert.selector, 0, "AA33 reverted", ""));
        entryPoint.handleOps(userOps, payable(BUNDLER));
    }

    function test_validatePaymasterUserOp_storesExecutionReceipt(uint256 amount, uint256 ethAmount)
        public
        fundAccount(signer.addr, amount)
        fundPaymaster(signer.addr, amount)
    {
        vm.assume(ethAmount > 0);

        PackedUserOperation[] memory userOps = _generateUserOps(signer.privateKey, ethAmount, address(0), 0);
        uint256 maxCost = this.calculateMaxCost(userOps[0]);

        vm.assume(ethAmount < type(uint256).max - maxCost && ethAmount + maxCost < amount);
        _deposit(maxCost);

        entryPoint.handleOps(userOps, payable(BUNDLER));

        assertEq(paymaster.requestHash(), entryPoint.getUserOpHash(userOps[0]));
        assertEq(paymaster.fulfiller(), address(signer.addr));
    }

    function test_validatePaymasterUserOp_doesNotStoreExecutionReceiptIfOpFails(uint256 amount)
        public
        fundAccount(signer.addr, amount)
        fundPaymaster(signer.addr, amount)
    {
        uint256 ethAmount = 0;
        PackedUserOperation[] memory userOps = _generateUserOps(signer.privateKey, ethAmount, address(0), 0);
        uint256 maxCost = this.calculateMaxCost(userOps[0]);

        vm.assume(ethAmount < type(uint256).max - maxCost && ethAmount + maxCost < amount);
        _deposit(maxCost);

        entryPoint.handleOps(userOps, payable(BUNDLER));

        assertEq(paymaster.requestHash(), bytes32(0));
        assertEq(paymaster.fulfiller(), address(0));
    }

    function test_validatePaymasterUserOp_decrementsMagicSpendBalance(uint256 amount, uint256 ethAmount)
        public
        fundAccount(signer.addr, amount)
        fundPaymaster(signer.addr, amount)
    {
        vm.assume(ethAmount > 0);

        PackedUserOperation[] memory userOps = _generateUserOps(signer.privateKey, ethAmount, address(0), 0);
        uint256 maxCost = this.calculateMaxCost(userOps[0]);

        vm.assume(ethAmount < type(uint256).max - maxCost && ethAmount + maxCost < amount);
        _deposit(maxCost);
        uint256 initialBalance = paymaster.getMagicSpendBalance(signer.addr);

        entryPoint.handleOps(userOps, payable(BUNDLER));

        assertEq(paymaster.getMagicSpendBalance(signer.addr), initialBalance - ethAmount);
    }

    function _generateUserOps(uint256 signerKey, uint256 ethAmount, address precheck, uint256 nonce)
        private
        view
        returns (PackedUserOperation[] memory)
    {
        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = PackedUserOperation({
            sender: address(mockAccount),
            nonce: nonce,
            initCode: "",
            callData: abi.encodeWithSelector(MockAccount.executeUserOp.selector, address(paymaster)),
            accountGasLimits: bytes32(abi.encodePacked(uint128(1000000), uint128(1000000))),
            preVerificationGas: 100000,
            gasFees: bytes32(abi.encodePacked(uint128(1000000), uint128(1000000))),
            paymasterAndData: "",
            signature: abi.encode(0)
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, _genDigest(userOps[0], ethAmount).toEthSignedMessageHash());
        userOps[0].paymasterAndData = _encodePaymasterAndData(abi.encodePacked(r, s, v), ethAmount, precheck);
        return userOps;
    }

    function _encodePaymasterAndData(bytes memory signature, uint256 ethAmount, address precheck)
        private
        view
        returns (bytes memory)
    {
        return abi.encodePacked(
            address(paymaster), uint128(1000000), uint128(1000000), abi.encode(ethAmount, signature, precheck)
        );
    }

    function _genDigest(PackedUserOperation memory userOp, uint256 ethAmount) private view returns (bytes32) {
        uint256 dstChainId = block.chainid;
        return keccak256(abi.encode(userOp.sender, userOp.nonce, userOp.callData, ethAmount, dstChainId));
    }

    function calculateMaxCost(PackedUserOperation calldata userOp) public view returns (uint256) {
        MemoryUserOp memory mUserOp;
        _copyUserOpToMemory(userOp, mUserOp);
        return _getRequiredPrefund(mUserOp);
    }

    function _deposit(uint256 amount) private {
        vm.prank(signer.addr);
        paymaster.entryPointDeposit(amount);
    }

    function _isValidWithdrawAddress(address withdrawAddress) private view {
        vm.assume(withdrawAddress.code.length == 0 && uint256(uint160(withdrawAddress)) > 65535);
    }
}
