
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import {Strings} from "@openzeppelin-contracts-5.0.1/utils/Strings.sol";
import {Proof} from "vlayer-0.1.0/Proof.sol";
import {Prover} from "vlayer-0.1.0/Prover.sol";
import {RegexLib} from "vlayer-0.1.0/Regex.sol";
import {VerifiedEmail, UnverifiedEmail, EmailProofLib} from "vlayer-0.1.0/EmailProof.sol";
import {AddressParser} from "./utils/AddressParser.sol";
import {WebLib} from "vlayer-0.1.0/WebProof.sol";
contract EmailProver is Prover {
    using Strings for string;
    using RegexLib for string;
    using AddressParser for string;
    using EmailProofLib for UnverifiedEmail;
    using WebLib for string;
    function main(UnverifiedEmail calldata unverifiedEmail) public view returns (
        Proof memory, 
        uint256 cleanliness, 
        uint256 communication, 
        uint256 houseRules
    ) {
        // Verify the email
        VerifiedEmail memory email = unverifiedEmail.verify();

        // Verify email metadata
        require(email.subject.equal("Fwd: Download your Airbnb account data"), "Invalid email subject");
        require(email.from.equal("madschristensen99@icloud.com"), "Invalid sender");
        // Get review content
        string memory content = email.body;

        // Count ratings for each category
        uint256 cleanlinessCount = 0;
        uint256 cleanlinessTotal = 0;
        uint256 communicationCount = 0;
        uint256 communicationTotal = 0;
        uint256 houseRulesCount = 0;
        uint256 houseRulesTotal = 0;
        // Regular expressions for each category and rating
        string[] memory ratings = new string[](3);
        ratings[0] = "3";
        ratings[1] = "4";
        ratings[2] = "5";
        // Parse cleanliness ratings
        for (uint i = 0; i < ratings.length; i++) {
            string memory pattern = string(abi.encodePacked(
                "^.\"ratingCategory\":\"CLEANLINESS\",\"ratingV2\":", 
                ratings[i],
                ".$"
            ));

            if (content.matches(pattern)) {
                cleanlinessTotal += (i + 3);  // 3, 4, or 5
                cleanlinessCount++;
            }
        }
        // Parse communication ratings
        for (uint i = 0; i < ratings.length; i++) {
            string memory pattern = string(abi.encodePacked(
                "^.\"ratingCategory\":\"COMMUNICATION\",\"ratingV2\":", 
                ratings[i],
                ".$"
            ));

            if (content.matches(pattern)) {
                communicationTotal += (i + 3);
                communicationCount++;
            }
        }
        // Parse house rules ratings
        for (uint i = 0; i < ratings.length; i++) {
            string memory pattern = string(abi.encodePacked(
                "^.\"ratingCategory\":\"RESPECT_HOUSE_RULES\",\"ratingV2\":", 
                ratings[i],
                ".$"
            ));

            if (content.matches(pattern)) {
                houseRulesTotal += (i + 3);
                houseRulesCount++;
            }
        }
        // Calculate averages (multiply by 10 for one decimal place)
        cleanliness = cleanlinessCount > 0 ? (cleanlinessTotal * 10) / cleanlinessCount : 0;
        communication = communicationCount > 0 ? (communicationTotal * 10) / communicationCount : 0;
        houseRules = houseRulesCount > 0 ? (houseRulesTotal * 10) / houseRulesCount : 0;
        return (proof(), cleanliness, communication, houseRules);
    }
}
