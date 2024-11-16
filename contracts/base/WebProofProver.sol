
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Strings} from "@openzeppelin-contracts-5.0.1/utils/Strings.sol";

import {Proof} from "vlayer-0.1.0/Proof.sol";
import {Prover} from "vlayer-0.1.0/Prover.sol";
import {Web, WebProof, WebProofLib, WebLib} from "vlayer-0.1.0/WebProof.sol";
import "./IOracle.sol";


contract WebProofProver is Prover {
    using Strings for string;
    using WebProofLib for WebProof;
    using WebLib for Web;

    string constant DATA_URL = "https://api.x.com/1.1/account/settings.json";

string prompt = "Turn this into three composite ratings 0-5 for cleanliness, house rules, and communication: Martina (June 2024)Mads is a great guest! I would like to present here the positive evaluation of our recent guest who we had in our Prague apartment. He was a really great guest who deserves my best rating. Communication with the guest was simple and pleasant. He was very accommodating and followed all the rules of our accommodation. During his stay, he showed considerable consideration and care for the space we provided him. The guest was also very clean and kept the apartment in excellent condition. He respected our equipment and facilities and did not cause any problems. We were delighted with how thoroughly he took care of our place.Christina (May 2024)Mads is very quiet. You hardly notice it.Erki (April 2024)Mads was nice guest, everything went smoothly.Michael (March 2024)Mads was a super easy guest. Hardly knew he was here.LuaHost (January 2024)Mads was a great guest and I would recommend Mads to any host!Paul (March 2023)Mads was \"Easy\". Quiet, clean and pleasant to have as a guest. Hardly knew he was here. Would like to have him return.Francisco (December 2022)Mads, was an amazing guestNicole (April 2022)Great guest! Would absolutely love to host Mads again!Janet (August 2021)Welcome back anytime, left our property in great condition.Daniel (June 2021)Mads left the place totally clean. A wonderful guest highly recommend you approve MadsLeague Furnished Housing (June 2021)Wonderful guest! Would host again anytime!Viagem (May 2021)Mads was a great guest. Very easy to communicate with, looked after the apartment as if it was their own. Everything left clean and tidy. Highly recommended to other hosts.Zencity (September 2020)Mads was a great guest - communicated well and respected the house rules. Mads is welcome back anytime!Zencity (August 2020)Mads was a great guest - communicated well and respected the house rules. Mads is welcome back anytime!Brad (August 2020)We give Mad's group 5 stars out of 5 stars. They were good communicators and left the house in good condition. We would gladly host them again.";


    function main(WebProof calldata webProof, address account)
        public
        returns (Proof memory, string memory, address, uint)
    {
        Web memory web = webProof.verify(DATA_URL);
        uint call = startChat(prompt);
        string memory screenName = web.jsonGetString("screen_name");

        return (proof(), screenName, account, call);
    }
     IOracle.LlmRequest private config;
    
    // @notice CID of the knowledge base
    string public knowledgeBase;

    // @notice Mapping from chat ID to the tool currently running
    mapping(uint => string) public toolRunning;

    // @notice Event emitted when the oracle address is updated
    event OracleAddressUpdated(address indexed newOracleAddress);
    address private owner;
     address public oracleAddress;
    // @param initialOracleAddress Initial address of the oracle contract
    constructor() {
        owner = msg.sender;
        oracleAddress = 0x40666E5B1cc80D139EE9145eFA3eD6ebF851Ae12;

        config = IOracle.LlmRequest({
            model : "claude-3-5-sonnet-20240620",
            frequencyPenalty : 21, // > 20 for null
            logitBias : "", // empty str for null
            maxTokens : 1000, // 0 for null
            presencePenalty : 21, // > 20 for null
            responseFormat : "{\"type\":\"text\"}",
            seed : 0, // null
            stop : "", // null
            temperature : 10, // Example temperature (scaled up, 10 means 1.0), > 20 means null
            topP : 101, // Percentage 0-100, > 100 means null
            tools : "[{\"type\":\"function\",\"function\":{\"name\":\"web_search\",\"description\":\"Search the internet\",\"parameters\":{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\",\"description\":\"Search query\"}},\"required\":[\"query\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"code_interpreter\",\"description\":\"Evaluates python code in a sandbox environment. The environment resets on every execution. You must send the whole script every time and print your outputs. Script should be pure python code that can be evaluated. It should be in python format NOT markdown. The code should NOT be wrapped in backticks. All python packages including requests, matplotlib, scipy, numpy, pandas, etc are available. Output can only be read from stdout, and stdin. Do not use things like plot.show() as it will not work. print() any output and results so you can capture the output.\",\"parameters\":{\"type\":\"object\",\"properties\":{\"code\":{\"type\":\"string\",\"description\":\"The pure python script to be evaluated. The contents will be in main.py. It should not be in markdown format.\"}},\"required\":[\"code\"]}}}]",
            toolChoice : "auto", // "none" or "auto"
            user : "" // null
        });
    }
    struct ChatRun {
        address owner;
        IOracle.Message[] messages;
        uint messagesCount;
    }

    // @notice Mapping from chat ID to ChatRun
    mapping(uint => ChatRun) public chatRuns;
    uint private chatRunsCount;

    // @notice Event emitted when a new chat is created
    event ChatCreated(address indexed owner, uint indexed chatId);
    
     // @notice Ensures the caller is the contract owner
    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not owner");
        _;
    }

    // @notice Ensures the caller is the oracle contract
    modifier onlyOracle() {
        require(msg.sender == oracleAddress, "Caller is not oracle");
        _;
    }

    // @notice Sets a new oracle address
    // @param newOracleAddress The new oracle address
    function setOracleAddress(address newOracleAddress) public onlyOwner {
        oracleAddress = newOracleAddress;
        emit OracleAddressUpdated(newOracleAddress);
    }

    // @notice Starts a new chat
    // @param message The initial message to start the chat with
    // @return The ID of the newly created chat
    function startChat(string memory message) public returns (uint) {
        ChatRun storage run = chatRuns[chatRunsCount];

        run.owner = msg.sender;
        IOracle.Message memory newMessage = createTextMessage("user", message);
        run.messages.push(newMessage);
        run.messagesCount++;

        uint currentId = chatRunsCount;
        chatRunsCount++;

        IOracle(oracleAddress).createLlmCall(currentId, config);
        emit ChatCreated(msg.sender, currentId);

        return currentId;
    }

    // @notice Handles the response from the oracle for an LLM call
    // @param runId The ID of the chat run
    // @param response The response from the oracle
    // @dev Called by teeML oracle
    function onOracleLlmResponse(
        uint runId,
        IOracle.LlmResponse memory response,
        string memory errorMessage
    ) public onlyOracle {
        ChatRun storage run = chatRuns[runId];
        require(
            keccak256(abi.encodePacked(run.messages[run.messagesCount - 1].role)) == keccak256(abi.encodePacked("user")),
            "No message to respond to"
        );

        if (!compareStrings(errorMessage, "")) {
            IOracle.Message memory newMessage = createTextMessage("assistant", errorMessage);
            run.messages.push(newMessage);
            run.messagesCount++;
        } else {
            if (!compareStrings(response.functionName, "")) {
                toolRunning[runId] = response.functionName;
                IOracle(oracleAddress).createFunctionCall(runId, response.functionName, response.functionArguments);
            } else {
                toolRunning[runId] = "";
            }
            IOracle.Message memory newMessage = createTextMessage("assistant", response.content);
            run.messages.push(newMessage);
            run.messagesCount++;
        }
    }
     // @notice Creates a text message with the given role and content
    // @param role The role of the message
    // @param content The content of the message
    // @return The created message
    function createTextMessage(string memory role, string memory content) private pure returns (IOracle.Message memory) {
        IOracle.Message memory newMessage = IOracle.Message({
            role: role,
            content: new IOracle.Content[](1)
        });
        newMessage.content[0].contentType = "text";
        newMessage.content[0].value = content;
        return newMessage;
    }

    // @notice Compares two strings for equality
    // @param a The first string
    // @param b The second string
    // @return True if the strings are equal, false otherwise
    function compareStrings(string memory a, string memory b) private pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }
     // @notice Adds a new message to an existing chat run
    // @param message The new message to add
    // @param runId The ID of the chat run
    function addMessage(string memory message, uint runId) public {
        ChatRun storage run = chatRuns[runId];
        require(
            keccak256(abi.encodePacked(run.messages[run.messagesCount - 1].role)) == keccak256(abi.encodePacked("assistant")),
            "No response to previous message"
        );
        require(
            run.owner == msg.sender, "Only chat owner can add messages"
        );

        IOracle.Message memory newMessage = createTextMessage("user", message);
        run.messages.push(newMessage);
        run.messagesCount++;
        // If there is a knowledge base, create a knowledge base query
        if (bytes(knowledgeBase).length > 0) {
            IOracle(oracleAddress).createKnowledgeBaseQuery(
                runId,
                knowledgeBase,
                message,
                3
            );
        } else {
            // Otherwise, create an LLM call
            IOracle(oracleAddress).createLlmCall(runId, config);
        }
    }

    // @notice Retrieves the message history of a chat run
    // @param chatId The ID of the chat run
    // @return An array of messages
    // @dev Called by teeML oracle
    function getMessageHistory(uint chatId) public view returns (IOracle.Message[] memory) {
        return chatRuns[chatId].messages;
    }
}
