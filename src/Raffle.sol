// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations (enums, structs etc...)
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {VRFConsumerBaseV2Plus} from
    "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title Lottery Smart Contract
 * @author Owanemi
 * @notice This contract is for creating a sample raffle
 * @dev Implements chainlink VRF 2.5
 */
contract Raffle is VRFConsumerBaseV2Plus {
    /* Errors */
    error Raffle__NotEnoughEth();
    error Raffle__NotEnoughTimePassed();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();

    /* Type declarations */
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    /* State Variables */
    uint256 private constant ENTRANCE_FEE = 0.1 ether;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint8 private constant NUM_WORDS = 1;
    // @dev how frequently our winner is going to be picked in seconds
    uint256 private immutable i_interval;
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    address payable[] private s_players;
    address private s_recentWinner;
    uint256 private s_lastTimeStamp;
    RaffleState private s_RaffleState;
    /* Events */

    event RaffleEntered(address indexed player, uint256 indexed amount);
    event WinnerPicked(address indexed winner);

    constructor(
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_interval = interval;
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_lastTimeStamp = block.timestamp;
        s_RaffleState = RaffleState.OPEN;
    }

    function enterRaffle() external payable {
        /* For version <0.8.24 */
        // require(msg.value >= ENTRANCE_FEE, "not enought eth");

        /* For version 0.8.24 */
        if (msg.value < ENTRANCE_FEE) {
            revert Raffle__NotEnoughEth();
        }
        s_players.push(payable(msg.sender));
        emit RaffleEntered(msg.sender, msg.value);

        /* For version 0.8.26 */

        //also less gas efficient and needs to compile with via-ir
        // require(msg.value >= ENTRANCE_FEE, NotEnoughEth());

        if(s_RaffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
    }

    function pickWinner() external {
        if ((block.timestamp - s_lastTimeStamp) > i_interval) {
            revert Raffle__NotEnoughTimePassed();
        }
        s_RaffleState = RaffleState.CALCULATING;
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient.RandomWordsRequest({
            keyHash: i_keyHash,
            subId: i_subscriptionId,
            requestConfirmations: REQUEST_CONFIRMATIONS,
            callbackGasLimit: i_callbackGasLimit,
            numWords: NUM_WORDS,
            extraArgs: VRFV2PlusClient._argsToBytes(
                // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
            )
        });
        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);
    }

    // i_entrance fee is stored on state so view function makes sense
    // however if entrance fee was a constant, pure function makes sense cos its not stored on state but embedded into bytecode
    // also if it was a regular state variable view would be used cos its stored in state

    /**
     * Getter functions
     */
    function getEntranceFee() external pure returns (uint256) {
        return ENTRANCE_FEE;
    }

    // CEIs(checks effects interactions)
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        // Checks

        // effects(Internal contract state)
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;

        // @dev after winner has been picked, the raffle state becomes open again
        s_RaffleState = RaffleState.OPEN;
        // @dev we reset the array after a winner has been picked 
        s_players = new address payable [](0);
        s_lastTimeStamp = block.timestamp;

        // Interactions
        (bool success,) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
        emit WinnerPicked(s_recentWinner);
    }
}
