// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IEntropyV2} from "lib/pyth-crosschain/target_chains/ethereum/entropy_sdk/solidity/IEntropyV2.sol";
import {IEntropyConsumer} from "lib/pyth-crosschain/target_chains/ethereum/entropy_sdk/solidity/IEntropyConsumer.sol";

interface IPixel {
    function mint(address account, uint256 amount) external;
}

contract Miner is IEntropyConsumer, ReentrancyGuard, Ownable {
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
    uint256 public constant DEFAULT_MULTIPLIER = 1e18;

    address public immutable pixel;
    address public immutable quote;
    uint256 public immutable startTime;

    IEntropyV2 entropy;
    address public treasury;

    uint256 public capacity = 256;
    uint256[] public multipliers;

    mapping(uint256 => Slot) public index_Slot;
    mapping(uint64 => uint256) public sequence_Index;
    mapping(uint64 => uint256) public sequence_Epoch;

    struct Slot {
        uint256 epochId;
        uint256 initPrice;
        uint256 startTime;
        uint256 pps;
        uint256 multiplier;
        address miner;
        string color;
    }

    error Miner__InvalidMiner();
    error Miner__InvalidIndex();
    error Miner__EpochIdMismatch();
    error Miner__MaxPriceExceeded();
    error Miner__Expired();
    error Miner__InsufficientFee();
    error Miner__InvalidTreasury();
    error Miner__CapacityBelowCurrent();
    error Miner__CapacityExceedsMax();
    error Miner__InvalidMultiplier();
    error Miner__InvalidLength();

    event Miner__Mine(
        address sender,
        address indexed miner,
        address indexed provider,
        uint256 indexed index,
        uint256 epochId,
        uint256 price,
        string color
    );
    event Miner__MultiplierSet(uint256 indexed index, uint256 indexed epochId, uint256 multiplier);
    event Miner__EntropyRequested(uint256 indexed index, uint256 indexed epochId, uint64 indexed sequenceNumber);
    event Miner__ProviderFee(address indexed provider, uint256 indexed index, uint256 indexed epochId, uint256 amount);
    event Miner__TreasuryFee(address indexed treasury, uint256 indexed index, uint256 indexed epochId, uint256 amount);
    event Miner__MinerFee(address indexed miner, uint256 indexed index, uint256 indexed epochId, uint256 amount);
    event Miner__Mint(address indexed miner, uint256 indexed index, uint256 indexed epochId, uint256 amount);
    event Miner__TreasurySet(address indexed treasury);
    event Miner__CapacitySet(uint256 capacity);
    event Miner__MultipliersSet(uint256[] multipliers);

    constructor(address _quote, address _pixel, address _entropy, address _treasury) {
        quote = _quote;
        pixel = _pixel;
        entropy = IEntropyV2(_entropy);
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
    ) external payable nonReentrant returns (uint256 price) {
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
        uint256 minedAmount = mineTime * slotCache.pps * slotCache.multiplier / PRECISION;

        if (slotCache.miner != address(0)) {
            IPixel(pixel).mint(slotCache.miner, minedAmount);
            emit Miner__Mint(slotCache.miner, index, epochId, minedAmount);
        }

        unchecked {
            slotCache.epochId++;
        }
        slotCache.initPrice = newInitPrice;
        slotCache.startTime = block.timestamp;
        slotCache.miner = miner;
        slotCache.multiplier = DEFAULT_MULTIPLIER;
        slotCache.pps = _getPpsFromTime(block.timestamp) / capacity;
        slotCache.color = color;

        index_Slot[index] = slotCache;

        emit Miner__Mine(msg.sender, miner, provider, index, epochId, price, color);

        uint128 fee = entropy.getFeeV2();
        if (msg.value < fee) revert Miner__InsufficientFee();
        uint64 seq = entropy.requestV2{value: fee}();
        sequence_Index[seq] = index;
        sequence_Epoch[seq] = slotCache.epochId;
        emit Miner__EntropyRequested(index, slotCache.epochId, seq);

        return price;
    }

    function entropyCallback(uint64 sequenceNumber, address, /*provider*/ bytes32 randomNumber) internal override {
        uint256 index = sequence_Index[sequenceNumber];
        uint256 epoch = sequence_Epoch[sequenceNumber];

        delete sequence_Index[sequenceNumber];
        delete sequence_Epoch[sequenceNumber];

        Slot memory slotCache = index_Slot[index];
        if (slotCache.epochId != epoch || slotCache.miner == address(0)) return;

        uint256 multiplier = _drawMultiplier(randomNumber);
        if (multiplier == 0) multiplier = DEFAULT_MULTIPLIER;
        slotCache.multiplier = multiplier;
        index_Slot[index] = slotCache;
        emit Miner__MultiplierSet(index, epoch, multiplier);
    }

    function _drawMultiplier(bytes32 randomNumber) internal view returns (uint256) {
        uint256 length = multipliers.length;
        if (length == 0) return DEFAULT_MULTIPLIER;
        uint256 idx = uint256(randomNumber) % length;
        return multipliers[idx];
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

    function setMultipliers(uint256[] calldata _multipliers) external onlyOwner {
        uint256 length = _multipliers.length;
        if (length == 0) revert Miner__InvalidLength();

        uint256 minMultiplier = DEFAULT_MULTIPLIER;
        for (uint256 i = 0; i < length; i++) {
            if (_multipliers[i] < minMultiplier) revert Miner__InvalidMultiplier();
        }

        multipliers = _multipliers;

        emit Miner__MultipliersSet(_multipliers);
    }

    function getEntropy() internal view override returns (address) {
        return address(entropy);
    }

    function getEntropyFee() external view returns (uint256) {
        return entropy.getFeeV2();
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

    function getMultipliers() external view returns (uint256[] memory) {
        return multipliers;
    }

    function getMultipliersLength() external view returns (uint256) {
        return multipliers.length;
    }
}
