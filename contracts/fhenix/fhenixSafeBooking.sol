// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Uncomment this line to use console.log
// import "hardhat/console.sol";
import "./contracts-main/contracts/contracts/interfaces/IOracle.sol";
import "@fhenixprotocol/contracts/FHE.sol";

// @title ChatGpt
// @notice This contract interacts with teeML oracle to handle chat interactions using the Anthropic model.
contract fheBooking {

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

    // @notice Address of the contract owner
    address private owner;
    
    // @notice Address of the oracle contract
    address public oracleAddress;

    // @notice Configuration for the LLM request
    IOracle.LlmRequest private config;
    
    // @notice CID of the knowledge base
    string public knowledgeBase;

    // @notice Mapping from chat ID to the tool currently running
    mapping(uint => string) public toolRunning;

    // @notice Event emitted when the oracle address is updated
    event OracleAddressUpdated(address indexed newOracleAddress);

    // @param initialOracleAddress Initial address of the oracle contract
    constructor(address initialOracleAddress) {
        owner = msg.sender;
        oracleAddress = initialOracleAddress;

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

        // Add initial system message to guide the AI
        string memory systemPrompt = "You are a helpful booking assistant. You can help users book accommodations "
            "by collecting their desired check-in and check-out dates. When users want to make a booking, extract the dates "
            "and call the createBooking function. Always confirm dates in UNIX timestamp format before proceeding. "
            "If dates are unclear, ask for clarification. Remember to check guest eligibility before proceeding with booking.";
        
        IOracle.Message memory systemMessage = createTextMessage("system", systemPrompt);
        run.messages.push(systemMessage);
        run.messagesCount++;

        // Add user's initial message
        IOracle.Message memory userMessage = createTextMessage("user", message);
        run.messages.push(userMessage);
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

    // @notice Handles the response from the oracle for a function call
    // @param runId The ID of the chat run
    // @param response The response from the oracle
    // @param errorMessage Any error message
    // @dev Called by teeML oracle
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

    // @notice Handles the response from the oracle for a knowledge base query
    // @param runId The ID of the chat run
    // @param documents The array of retrieved documents
    // @dev Called by teeML oracle
    function onOracleKnowledgeBaseQueryResponse(
        uint runId,
        string[] memory documents,
        string memory /*errorMessage*/
    ) public onlyOracle {
        ChatRun storage run = chatRuns[runId];
        require(
            keccak256(abi.encodePacked(run.messages[run.messagesCount - 1].role)) == keccak256(abi.encodePacked("user")),
            "No message to add context to"
        );
        // Retrieve the last user message
        IOracle.Message storage lastMessage = run.messages[run.messagesCount - 1];

        // Start with the original message content
        string memory newContent = lastMessage.content[0].value;

        // Append "Relevant context:\n" only if there are documents
        if (documents.length > 0) {
            newContent = string(abi.encodePacked(newContent, "\n\nRelevant context:\n"));
        }

        // Iterate through the documents and append each to the newContent
        for (uint i = 0; i < documents.length; i++) {
            newContent = string(abi.encodePacked(newContent, documents[i], "\n"));
        }

        // Finally, set the lastMessage content to the newly constructed string
        lastMessage.content[0].value = newContent;

        // Call LLM
        IOracle(oracleAddress).createLlmCall(runId, config);
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
    struct GuestRating {
        euint8 cleanliness;     // 0-50 score
        euint8 communication;   // 0-50 score
        euint8 houseRules;      // 0-50 score
        euint8 bookingCount;    // Number of bookings made
    }

    // Booking structure
    struct Booking {
        address guest;
        uint256 checkIn;
        uint256 checkOut;
        bool isActive;
        uint256 securityDeposit;
    }
    // Security deposit constants
    uint256 public constant BASE_DEPOSIT = 0.5 ether;    // Base deposit amount
    uint256 public constant MIN_DEPOSIT = 0.1 ether;     // Minimum deposit for highest rated guests
    uint256 public constant MAX_DEPOSIT = 1 ether;       // Maximum deposit for new/low rated guests
    // Calculate required security deposit based on guest rating
    function calculateSecurityDeposit(address guest) public view returns (uint256) {
        GuestRating storage rating = guestRatings[guest];
        
        // For new guests with no ratings, require maximum deposit
        if (FHE.decrypt(rating.bookingCount) == 0) {
            return MAX_DEPOSIT;
        }
        
        // Calculate average score
        euint8 totalScore = rating.cleanliness + rating.communication + rating.houseRules;
        euint8 averageScore = totalScore / FHE.asEuint8(3);
        uint8 decryptedScore = FHE.decrypt(averageScore);
        
        // Calculate deposit reduction based on score
        // Score of 50 = minimum deposit
        // Score of 30 (minimum required) = base deposit
        // Score below 30 = maximum deposit
        if (decryptedScore >= 45) {
            return MIN_DEPOSIT;
        } else if (decryptedScore >= 30) {
            // Linear interpolation between base and minimum deposit
            uint256 scoreAboveMin = decryptedScore - 30;
            uint256 reduction = (BASE_DEPOSIT - MIN_DEPOSIT) * scoreAboveMin / 15;
            return BASE_DEPOSIT - reduction;
        } else {
            return MAX_DEPOSIT;
        }
    }
    // State variables
    mapping(address => GuestRating) private guestRatings;
    mapping(uint256 => Booking) public bookings;
    uint256 private nextBookingId;
    uint256 public minimumRequiredScore = 30; // Minimum score required (out of 50)

    // Events
    event BookingCreated(uint256 indexed bookingId, address indexed guest, uint256 checkIn, uint256 checkOut);
    event BookingCancelled(uint256 indexed bookingId);
    event RatingUpdated(address indexed guest);

    // Initialize a new guest's ratings
    function initializeGuest(inEuint8 calldata cleanliness, inEuint8 calldata communication, inEuint8 calldata houseRules) public {
        GuestRating storage rating = guestRatings[msg.sender];
        
        // Convert input encrypted values to euint8
        rating.cleanliness = FHE.asEuint8(cleanliness);
        rating.communication = FHE.asEuint8(communication);
        rating.houseRules = FHE.asEuint8(houseRules);
        rating.bookingCount = FHE.asEuint8(0);
    }

    // Check if guest meets minimum requirements (returns encrypted boolean)
    function checkGuestEligibility(address guest) public view returns (ebool) {
        GuestRating storage rating = guestRatings[guest];
        
        // Calculate average score (all scores are 0-50)
        euint8 totalScore = rating.cleanliness + rating.communication + rating.houseRules;
        euint8 averageScore = totalScore / FHE.asEuint8(3);
        
        // Check if average score meets minimum requirement
        return averageScore.gte(FHE.asEuint8(minimumRequiredScore));
    }

    // Modified createBooking function to handle security deposit
    function createBooking(uint256 checkIn, uint256 checkOut) public payable returns (uint256) {
        require(checkIn < checkOut, "Invalid booking dates");
        require(checkIn > block.timestamp, "Cannot book in the past");
        
        // Check if guest meets minimum rating requirements
        ebool isEligible = checkGuestEligibility(msg.sender);
        require(FHE.decrypt(isEligible), "Guest does not meet minimum rating requirements");

        // Calculate required security deposit
        uint256 requiredDeposit = calculateSecurityDeposit(msg.sender);
        require(msg.value >= requiredDeposit, "Insufficient security deposit");

        // Create the booking
        uint256 bookingId = nextBookingId++;
        bookings[bookingId] = Booking({
            guest: msg.sender,
            checkIn: checkIn,
            checkOut: checkOut,
            isActive: true,
            securityDeposit: msg.value
        });

        // Increment booking count for guest
        GuestRating storage rating = guestRatings[msg.sender];
        rating.bookingCount = rating.bookingCount + FHE.asEuint8(1);

        return bookingId;
    }

    // Modified cancelBooking function to handle deposit refund
    function cancelBooking(uint256 bookingId) public {
        Booking storage booking = bookings[bookingId];
        require(booking.isActive, "Booking is not active");
        require(msg.sender == booking.guest, "Only guest can cancel booking");
        require(booking.checkIn > block.timestamp, "Cannot cancel past bookings");
        
        uint256 depositToReturn = booking.securityDeposit;
        booking.securityDeposit = 0;
        booking.isActive = false;
        
        // Return the security deposit to the guest
        (bool success, ) = booking.guest.call{value: depositToReturn}("");
        require(success, "Failed to return security deposit");
        
        emit BookingCancelled(bookingId);
    }

    // Function to return security deposit after successful stay
    function returnDeposit(uint256 bookingId) public {
        Booking storage booking = bookings[bookingId];
        require(booking.isActive, "Booking is not active");
        require(block.timestamp > booking.checkOut, "Booking hasn't ended yet");
        require(msg.sender == owner, "Only owner can return deposit");
        
        uint256 depositToReturn = booking.securityDeposit;
        booking.securityDeposit = 0;
        booking.isActive = false;
        
        // Return the security deposit to the guest
        (bool success, ) = booking.guest.call{value: depositToReturn}("");
        require(success, "Failed to return security deposit");
        
    }


    // Update guest ratings (only callable by authorized raters)
    function updateGuestRating(
        address guest,
        inEuint8 calldata newCleanliness,
        inEuint8 calldata newCommunication,
        inEuint8 calldata newHouseRules
    ) public {
        // In a real implementation, add access control here
        //require(msg.sender == owner(), "Only authorized raters can update ratings");
        
        GuestRating storage rating = guestRatings[guest];
        
        // Calculate weighted average with existing scores
        euint8 bookingCount = rating.bookingCount;
        ebool hasExistingBookings = bookingCount.gt(FHE.asEuint8(0));
        
        // For each category, calculate: (oldScore * bookingCount + newScore) / (bookingCount + 1)
        euint8 denominator = bookingCount + FHE.asEuint8(1);
        
        // Update cleanliness
        euint8 weightedCleanliness = (rating.cleanliness * bookingCount + FHE.asEuint8(newCleanliness)) / denominator;
        rating.cleanliness = FHE.select(hasExistingBookings, weightedCleanliness, FHE.asEuint8(newCleanliness));
        
        // Update communication
        euint8 weightedCommunication = (rating.communication * bookingCount + FHE.asEuint8(newCommunication)) / denominator;
        rating.communication = FHE.select(hasExistingBookings, weightedCommunication, FHE.asEuint8(newCommunication));
        
        // Update house rules
        euint8 weightedHouseRules = (rating.houseRules * bookingCount + FHE.asEuint8(newHouseRules)) / denominator;
        rating.houseRules = FHE.select(hasExistingBookings, weightedHouseRules, FHE.asEuint8(newHouseRules));
        
        emit RatingUpdated(guest);
    }


    // Get encrypted rating summary (only the guest can decrypt these values)
    function getGuestRating(address guest) public view returns (
        euint8 cleanliness,
        euint8 communication,
        euint8 houseRules,
        euint8 bookingCount
    ) {
        GuestRating storage rating = guestRatings[guest];
        return (
            rating.cleanliness,
            rating.communication,
            rating.houseRules,
            rating.bookingCount
        );
    }
}
