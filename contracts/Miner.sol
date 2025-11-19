// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IPixel {
    function mint(address account, uint256 amount) external;
}

contract Miner is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    uint256 public constant FEE = 2_000;
    uint256 public constant DIVISOR = 10_000;
    uint256 public constant PRECISION = 1e18;

    uint256 public constant EPOCH_PERIOD = 1 hours;
    uint256 public constant PRICE_MULTIPLIER = 2e18;
    uint256 public constant MIN_INIT_PRICE = 0.0001 ether;
    uint256 public constant ABS_MAX_INIT_PRICE = type(uint192).max;

    uint256 public constant INITIAL_PPS = 2 ether;
    uint256 public constant HALVING_PERIOD = 30 days;
    uint256 public constant TAIL_PPS = 0.01 ether;
    uint256 public constant MAX_CAPACITY = 1024;

    address public immutable pixel;
    address public immutable quote;
    uint256 public immutable startTime;
    address public treasury;

    uint256 public capacity = 256;

    mapping(uint256 => Slot) public index_Slot;

    struct Slot {
        uint256 epochId;
        uint256 initPrice;
        uint256 startTime;
        uint256 pps;
        address miner;
        string color;
    }

    error Miner__InvalidMiner();
    error Miner__InvalidIndex();
    error Miner__EpochIdMismatch();
    error Miner__MaxPriceExceeded();
    error Miner__InvalidTreasury();
    error Miner__CapacityBelowCurrent();
    error Miner__CapacityExceedsMax();
    error Miner__Expired();

    event Miner__Mine(
        address sender,
        address indexed miner,
        address indexed provider,
        uint256 indexed index,
        uint256 epochId,
        uint256 price,
        string color
    );
    event Miner__ProviderFee(address indexed provider, uint256 indexed index, uint256 indexed epochId, uint256 amount);
    event Miner__TreasuryFee(address indexed treasury, uint256 indexed index, uint256 indexed epochId, uint256 amount);
    event Miner__MinerFee(address indexed miner, uint256 indexed index, uint256 indexed epochId, uint256 amount);
    event Miner__Mint(address indexed miner, uint256 indexed index, uint256 indexed epochId, uint256 amount);
    event Miner__TreasurySet(address indexed treasury);
    event Miner__CapacitySet(uint256 capacity);

    constructor(address _quote, address _pixel, address _treasury) {
        quote = _quote;
        pixel = _pixel;
        treasury = _treasury;
        startTime = block.timestamp;
    }

    function mine(
        address miner,
        address provider,
        uint256 index,
        uint256 epochId,
        uint256 deadline,
        uint256 maxPrice,
        string memory color
    ) external nonReentrant returns (uint256 price) {
        if (miner == address(0)) revert Miner__InvalidMiner();
        if (block.timestamp > deadline) revert Miner__Expired();
        if (index >= capacity) revert Miner__InvalidIndex();

        Slot memory slotCache = index_Slot[index];

        if (epochId != slotCache.epochId) revert Miner__EpochIdMismatch();

        price = _getPriceFromCache(slotCache);
        if (price > maxPrice) revert Miner__MaxPriceExceeded();

        if (price > 0) {
            uint256 totalFee = price * FEE / DIVISOR;
            uint256 minerFee = price - totalFee;
            uint256 providerFee = 0;
            uint256 treasuryFee = 0;

            if (provider == address(0)) {
                treasuryFee = totalFee;
            } else {
                providerFee = totalFee / 4;
                treasuryFee = totalFee - providerFee;
            }

            if (providerFee > 0) {
                IERC20(quote).safeTransferFrom(msg.sender, provider, providerFee);
                emit Miner__ProviderFee(provider, index, epochId, providerFee);
            }

            IERC20(quote).safeTransferFrom(msg.sender, treasury, treasuryFee);
            emit Miner__TreasuryFee(treasury, index, epochId, treasuryFee);

            IERC20(quote).safeTransferFrom(msg.sender, slotCache.miner, minerFee);
            emit Miner__MinerFee(slotCache.miner, index, epochId, minerFee);
        }

        uint256 newInitPrice = price * PRICE_MULTIPLIER / PRECISION;

        if (newInitPrice > ABS_MAX_INIT_PRICE) {
            newInitPrice = ABS_MAX_INIT_PRICE;
        } else if (newInitPrice < MIN_INIT_PRICE) {
            newInitPrice = MIN_INIT_PRICE;
        }

        uint256 mineTime = block.timestamp - slotCache.startTime;
        uint256 minedAmount = mineTime * slotCache.pps;

        IPixel(pixel).mint(slotCache.miner, minedAmount);
        emit Miner__Mint(slotCache.miner, index, epochId, minedAmount);

        unchecked {
            slotCache.epochId++;
        }
        slotCache.initPrice = newInitPrice;
        slotCache.startTime = block.timestamp;
        slotCache.miner = miner;
        slotCache.pps = _getPpsFromTime(block.timestamp) / capacity;
        slotCache.color = color;

        index_Slot[index] = slotCache;

        emit Miner__Mine(msg.sender, miner, provider, index, epochId, price, color);

        return price;
    }

    function _getPriceFromCache(Slot memory slotCache) internal view returns (uint256) {
        uint256 timePassed = block.timestamp - slotCache.startTime;

        if (timePassed > EPOCH_PERIOD) {
            return 0;
        }

        return slotCache.initPrice - slotCache.initPrice * timePassed / EPOCH_PERIOD;
    }

    function _getPpsFromTime(uint256 time) internal view returns (uint256 pps) {
        uint256 halvings = time <= startTime ? 0 : (time - startTime) / HALVING_PERIOD;
        pps = INITIAL_PPS >> halvings;
        if (pps < TAIL_PPS) pps = TAIL_PPS;
        return pps;
    }

    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert Miner__InvalidTreasury();
        treasury = _treasury;
        emit Miner__TreasurySet(_treasury);
    }

    function setCapacity(uint256 _capacity) external onlyOwner {
        if (_capacity <= capacity) revert Miner__CapacityBelowCurrent();
        if (_capacity > MAX_CAPACITY) revert Miner__CapacityExceedsMax();
        capacity = _capacity;
        emit Miner__CapacitySet(_capacity);
    }

    function getPrice(uint256 index) external view returns (uint256) {
        return _getPriceFromCache(index_Slot[index]);
    }

    function getPps() external view returns (uint256) {
        return _getPpsFromTime(block.timestamp);
    }

    function getSlot(uint256 index) external view returns (Slot memory) {
        return index_Slot[index];
    }
}
