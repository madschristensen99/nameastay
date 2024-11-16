// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {EmailProver} from "./EmailProver.sol";
import {Proof} from "vlayer-0.1.0/Proof.sol";
import {Verifier} from "vlayer-0.1.0/Verifier.sol";
import "./IOracle.sol";

contract TravelGuideChat is Verifier {
    struct VendorInfo {
        string name;
        string category;
        string location;
        address payable vendorAddress;
        uint256 baseCommissionRate;
        bool isActive;
        uint256 totalBookings;
        uint256 totalCommissions;
    }

    struct Booking {
        address user;
        uint256 vendorId;
        uint256 amount;
        uint256 commission;
        uint256 timestamp;
        bool isCompleted;
    }

    struct ChatRun {
        address owner;
        IOracle.Message[] messages;
        uint messagesCount;
        bool hasVerifiedRating;
    }

    address public prover;
    address public oracleAddress;
    address public treasury;
    
    mapping(uint => ChatRun) public chatRuns;
    uint private chatRunsCount;
    
    mapping(uint256 => VendorInfo) public vendors;
    uint256 public vendorCount;
    
    mapping(uint256 => Booking) public bookings;
    uint256 public bookingCount;
    
    mapping(address => uint256[]) public userBookings;
    mapping(uint256 => uint256[]) public vendorBookings;
    
    mapping(uint => string) public toolRunning;
    string public knowledgeBase;
    
    event ChatCreated(address indexed owner, uint indexed chatId);
    event VendorAdded(uint256 indexed vendorId, string name, string category);
    event VendorUpdated(uint256 indexed vendorId, string name, string category);
    event BookingCreated(uint256 indexed bookingId, address indexed user, uint256 indexed vendorId, uint256 amount);
    event CommissionPaid(uint256 indexed vendorId, uint256 amount);
    event OracleAddressUpdated(address indexed newOracleAddress);
    
    IOracle.LlmRequest private config;

    constructor(address _prover, address _treasury) {
        prover = _prover;
        treasury = _treasury;
        oracleAddress = 0x03d42AB95f54DEe5d3Ce7db984237b340f458988;

        config = IOracle.LlmRequest({
            model: "claude-3-5-sonnet-20240620",
            frequencyPenalty: 21,
            logitBias: "",
            maxTokens: 1000,
            presencePenalty: 21,
            responseFormat: "{\"type\":\"text\"}",
            seed: 0,
            stop: "",
            temperature: 10,
            topP: 101,
            tools: "[{\"type\":\"function\",\"function\":{\"name\":\"search_vendors\",\"description\":\"Search for travel vendors by category and location\",\"parameters\":{\"type\":\"object\",\"properties\":{\"category\":{\"type\":\"string\",\"description\":\"Type of vendor\"},\"location\":{\"type\":\"string\",\"description\":\"Location to search in\"}},\"required\":[\"category\",\"location\"]}}}]",
            toolChoice: "auto",
            user: ""
        });

        // Add sample vendors with payment addresses
        addVendor(
            "Luxury Hotel Paradise",
            "Hotel",
            "Bali",
            payable(0x1234567890123456789012345678901234567890),
            250
        );
        addVendor(
            "Adventure Tours Co",
            "Tour",
            "Costa Rica",
            payable(0x2234567890123456789012345678901234567890),
            500
        );
        addVendor(
            "Local Eats & Treats",
            "Restaurant",
            "Tokyo",
            payable(0x3234567890123456789012345678901234567890),
            300
        );
        addVendor(
            "Beach Resort & Spa",
            "Hotel",
            "Maldives",
            payable(0x4234567890123456789012345678901234567890),
            400
        );
    }

    modifier onlyOracle() {
        require(msg.sender == oracleAddress, "Not oracle");
        _;
    }

    modifier onlyProver() {
        require(msg.sender == prover, "Not authorized");
        _;
    }

    function verify(Proof calldata proof, uint clean, uint comms, uint rules) public view onlyVerified(prover, EmailProver.main.selector) {
        // Verification handled by modifier
    }

    function addVendor(
        string memory name,
        string memory category,
        string memory location,
        address payable vendorAddress,
        uint256 baseCommissionRate
    ) public onlyProver {
        require(baseCommissionRate <= 1000, "Commission rate too high"); // Max 10%
        require(vendorAddress != address(0), "Invalid vendor address");
        
        uint256 vendorId = vendorCount++;
        vendors[vendorId] = VendorInfo({
            name: name,
            category: category,
            location: location,
            vendorAddress: vendorAddress,
            baseCommissionRate: baseCommissionRate,
            isActive: true,
            totalBookings: 0,
            totalCommissions: 0
        });

        emit VendorAdded(vendorId, name, category);
    }

    function updateVendor(
        uint256 vendorId,
        string memory name,
        string memory category,
        string memory location,
        address payable vendorAddress,
        uint256 baseCommissionRate,
        bool isActive
    ) public onlyProver {
        require(vendorId < vendorCount, "Vendor does not exist");
        require(baseCommissionRate <= 1000, "Commission rate too high");
        require(vendorAddress != address(0), "Invalid vendor address");

        VendorInfo storage vendor = vendors[vendorId];
        vendor.name = name;
        vendor.category = category;
        vendor.location = location;
        vendor.vendorAddress = vendorAddress;
        vendor.baseCommissionRate = baseCommissionRate;
        vendor.isActive = isActive;

        emit VendorUpdated(vendorId, name, category);
    }

    function createBooking(uint256 vendorId) public payable {
        require(vendorId < vendorCount, "Vendor does not exist");
        require(vendors[vendorId].isActive, "Vendor is not active");
        require(msg.value > 0, "Booking amount must be greater than 0");

        VendorInfo storage vendor = vendors[vendorId];
        uint256 commission = (msg.value * vendor.baseCommissionRate) / 10000;
        
        uint256 bookingId = bookingCount++;
        bookings[bookingId] = Booking({
            user: msg.sender,
            vendorId: vendorId,
            amount: msg.value,
            commission: commission,
            timestamp: block.timestamp,
            isCompleted: false
        });

        userBookings[msg.sender].push(bookingId);
        vendorBookings[vendorId].push(bookingId);
        
        vendor.totalBookings++;
        vendor.totalCommissions += commission;

        // Transfer commission to treasury
        payable(treasury).transfer(commission);
        // Transfer remaining amount to vendor's address
        vendor.vendorAddress.transfer(msg.value - commission);

        emit BookingCreated(bookingId, msg.sender, vendorId, msg.value);
        emit CommissionPaid(vendorId, commission);
    }

    function startTravelGuideChat(string memory initialMessage) public returns (uint) {
        ChatRun storage run = chatRuns[chatRunsCount];
        run.owner = msg.sender;
        
        string memory systemPrompt = "You are a travel guide AI assistant. You help travelers find the best experiences and can recommend verified vendors in our network. Please provide detailed information about destinations and help users make informed travel decisions.";
        
        IOracle.Message memory systemMessage = createTextMessage("system", systemPrompt);
        run.messages.push(systemMessage);
        run.messagesCount++;
        
        IOracle.Message memory userMessage = createTextMessage("user", initialMessage);
        run.messages.push(userMessage);
        run.messagesCount++;

        uint currentId = chatRunsCount;
        chatRunsCount++;

        IOracle(oracleAddress).createLlmCall(currentId, config);
        emit ChatCreated(msg.sender, currentId);

        return currentId;
    }

    function addMessage(string memory message, uint runId) public {
        ChatRun storage run = chatRuns[runId];
        require(run.owner == msg.sender, "Not chat owner");
        require(
            keccak256(abi.encodePacked(run.messages[run.messagesCount - 1].role)) == 
            keccak256(abi.encodePacked("assistant")),
            "Waiting for assistant response"
        );

        IOracle.Message memory newMessage = createTextMessage("user", message);
        run.messages.push(newMessage);
        run.messagesCount++;

        if (bytes(knowledgeBase).length > 0) {
            IOracle(oracleAddress).createKnowledgeBaseQuery(
                runId,
                knowledgeBase,
                message,
                3
            );
        } else {
            IOracle(oracleAddress).createLlmCall(runId, config);
        }
    }

    function onOracleLlmResponse(
        uint runId,
        IOracle.LlmResponse memory response,
        string memory errorMessage
    ) public onlyOracle {
        ChatRun storage run = chatRuns[runId];
        require(
            keccak256(abi.encodePacked(run.messages[run.messagesCount - 1].role)) == 
            keccak256(abi.encodePacked("user")),
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

    function onOracleFunctionResponse(
        uint runId,
        string memory response,
        string memory errorMessage
    ) public onlyOracle {
        require(
            !compareStrings(toolRunning[runId], ""),
            "No function to respond to"
        );
        ChatRun storage run = chatRuns[runId];
        if (compareStrings(errorMessage, "")) {
            IOracle.Message memory newMessage = createTextMessage("user", response);
            run.messages.push(newMessage);
            run.messagesCount++;
            IOracle(oracleAddress).createLlmCall(runId, config);
        }
    }

    function onOracleKnowledgeBaseQueryResponse(
        uint runId,
        string[] memory documents,
        string memory errorMessage
    ) public onlyOracle {
        ChatRun storage run = chatRuns[runId];
        require(
            keccak256(abi.encodePacked(run.messages[run.messagesCount - 1].role)) == 
            keccak256(abi.encodePacked("user")),
            "No message to add context to"
        );

        IOracle.Message storage lastMessage = run.messages[run.messagesCount - 1];
        string memory newContent = lastMessage.content[0].value;

        if (documents.length > 0) {
            newContent = string(abi.encodePacked(newContent, "\n\nRelevant context:\n"));
        }

        for (uint i = 0; i < documents.length; i++) {
            newContent = string(abi.encodePacked(newContent, documents[i], "\n"));
        }

        lastMessage.content[0].value = newContent;
        IOracle(oracleAddress).createLlmCall(runId, config);
    }

    function getMessageHistory(uint chatId) public view returns (IOracle.Message[] memory) {
        return chatRuns[chatId].messages;
    }

    function getVendorsByCategory(string memory category) public view returns (uint256[] memory) {
        uint256[] memory result = new uint256[](vendorCount);
        uint256 count = 0;
        
        for (uint256 i = 0; i < vendorCount; i++) {
            if (compareStrings(vendors[i].category, category) && vendors[i].isActive) {
                result[count] = i;
                count++;
            }
        }
        
        assembly {
            mstore(result, count)
        }
        
        return result;
    }

    function getVendorsByLocation(string memory location) public view returns (uint256[] memory) {
        uint256[] memory result = new uint256[](vendorCount);
        uint256 count = 0;
        
        for (uint256 i = 0; i < vendorCount; i++) {
            if (compareStrings(vendors[i].location, location) && vendors[i].isActive) {
                result[count] = i;
                count++;
            }
        }
        
        assembly {
            mstore(result, count)
        }
        
        return result;
    }

    function getUserBookings(address user) public view returns (uint256[] memory) {
        return userBookings[user];
    }

    function getVendorBookings(uint256 vendorId) public view returns (uint256[] memory) {
        return vendorBookings[vendorId];
    }

    function createTextMessage(string memory role, string memory content) private pure returns (IOracle.Message memory) {
        IOracle.Message memory newMessage = IOracle.Message({
            role: role,
            content: new IOracle.Content[](1)
        });
        newMessage.content[0].contentType = "text";
        newMessage.content[0].value = content;
        return newMessage;
    }

    function compareStrings(string memory a, string memory b) private pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }

    function setOracleAddress(address newAddress) public onlyProver {
        oracleAddress = newAddress;
        emit OracleAddressUpdated(newAddress);
    }

    function setProver(address newProver) public onlyProver {
        prover = newProver;
    }

    function setKnowledgeBase(string memory newKnowledgeBase) public onlyProver {
        knowledgeBase = newKnowledgeBase;
    }

    function setTreasury(address newTreasury) public onlyProver {
        treasury = newTreasury;
    }
}
