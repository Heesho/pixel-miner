// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IWETH {
    function deposit() external payable;
}

interface IMiner {
    struct Slot {
        uint256 epochId;
        uint256 initPrice;
        uint256 startTime;
        uint256 pps;
        address miner;
        string color;
    }

    function pixel() external view returns (address);
    function quote() external view returns (address);
    function startTime() external view returns (uint256);
    function capacity() external view returns (uint256);
    function index_Slot(uint256 index) external view returns (Slot memory);
    function getPrice(uint256 index) external view returns (uint256);
    function getPps() external view returns (uint256);

    function mine(
        address miner,
        address provider,
        uint256 index,
        uint256 epochId,
        uint256 deadline,
        uint256 maxPrice,
        string memory color
    ) external returns (uint256 price);
}

interface IAuction {
    struct Slot0 {
        uint8 locked;
        uint16 epochId;
        uint192 initPrice;
        uint40 startTime;
    }

    function paymentToken() external view returns (address);
    function getPrice() external view returns (uint256);
    function getSlot0() external view returns (Slot0 memory);
    function buy(
        address[] calldata assets,
        address assetsReceiver,
        uint256 epochId,
        uint256 deadline,
        uint256 maxPaymentTokenAmount
    ) external;
}

contract Multicall is Ownable {
    using SafeERC20 for IERC20;

    address public immutable miner;
    address public immutable pixel;
    address public immutable quote;

    address public auction;

    struct MinerState {
        uint256 pps;
        uint256 pixelPrice;
        uint256 pixelBalance;
        uint256 ethBalance;
        uint256 wethBalance;
    }

    struct SlotState {
        uint256 epochId;
        uint256 initPrice;
        uint256 startTime;
        uint256 price;
        uint256 pps;
        uint256 mined;
        address miner;
        string color;
    }

    struct AuctionState {
        uint16 epochId;
        uint192 initPrice;
        uint40 startTime;
        address paymentToken;
        uint256 price;
        uint256 paymentTokenPrice;
        uint256 wethAccumulated;
        uint256 wethBalance;
        uint256 paymentTokenBalance;
    }

    constructor(address _miner) {
        miner = _miner;
        pixel = IMiner(miner).pixel();
        quote = IMiner(miner).quote();
    }

    function mine(
        address provider,
        uint256 index,
        uint256 epochId,
        uint256 deadline,
        uint256 maxPrice,
        string memory color
    ) external payable {
        IWETH(quote).deposit{value: msg.value}();
        IERC20(quote).safeApprove(miner, 0);
        IERC20(quote).safeApprove(miner, msg.value);
        IMiner(miner).mine(msg.sender, provider, index, epochId, deadline, maxPrice, color);
        uint256 wethBalance = IERC20(quote).balanceOf(address(this));
        IERC20(quote).safeTransfer(msg.sender, wethBalance);
    }

    function buy(uint256 epochId, uint256 deadline, uint256 maxPaymentTokenAmount) external {
        address paymentToken = IAuction(auction).paymentToken();
        uint256 price = IAuction(auction).getPrice();
        address[] memory assets = new address[](1);
        assets[0] = quote;

        IERC20(paymentToken).safeTransferFrom(msg.sender, address(this), price);
        IERC20(paymentToken).safeApprove(auction, 0);
        IERC20(paymentToken).safeApprove(auction, price);
        IAuction(auction).buy(assets, msg.sender, epochId, deadline, maxPaymentTokenAmount);
    }

    function setAuction(address _auction) external onlyOwner {
        auction = _auction;
    }

    function getMiner(address account) external view returns (MinerState memory state) {
        state.pps = IMiner(miner).getPps();
        if (auction != address(0)) {
            address paymentToken = IAuction(auction).paymentToken();
            uint256 quoteInLP = IERC20(quote).balanceOf(paymentToken);
            uint256 pixelInLP = IERC20(pixel).balanceOf(paymentToken);
            state.pixelPrice = pixelInLP == 0 ? 0 : quoteInLP * 1e18 / pixelInLP;
        }
        state.pixelBalance = account == address(0) ? 0 : IERC20(pixel).balanceOf(account);
        state.ethBalance = account == address(0) ? 0 : account.balance;
        state.wethBalance = account == address(0) ? 0 : IERC20(quote).balanceOf(account);
        return state;
    }

    function getAuction(address account) external view returns (AuctionState memory state) {
        IAuction.Slot0 memory slot0 = IAuction(auction).getSlot0();
        state.epochId = slot0.epochId;
        state.initPrice = slot0.initPrice;
        state.startTime = slot0.startTime;
        state.paymentToken = IAuction(auction).paymentToken();
        state.price = IAuction(auction).getPrice();
        state.paymentTokenPrice =
            IERC20(quote).balanceOf(state.paymentToken) * 2e18 / IERC20(state.paymentToken).totalSupply();
        state.wethAccumulated = IERC20(quote).balanceOf(auction);
        state.wethBalance = account == address(0) ? 0 : IERC20(quote).balanceOf(account);
        state.paymentTokenBalance = account == address(0) ? 0 : IERC20(state.paymentToken).balanceOf(account);
        return state;
    }

    function getSlot(uint256 index) public view returns (SlotState memory state) {
        IMiner.Slot memory slot = IMiner(miner).index_Slot(index);
        state.epochId = slot.epochId;
        state.initPrice = slot.initPrice;
        state.startTime = slot.startTime;
        state.price = IMiner(miner).getPrice(index);
        state.pps = slot.pps;
        state.mined = state.pps * (block.timestamp - state.startTime);
        state.miner = slot.miner;
        state.color = slot.color;
        return state;
    }

    function getSlots(uint256 startIndex, uint256 endIndex) external view returns (SlotState[] memory states) {
        states = new SlotState[](endIndex - startIndex + 1);
        for (uint256 i = startIndex; i <= endIndex; i++) {
            states[i - startIndex] = getSlot(i);
        }
        return states;
    }
}
