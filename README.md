# Name a Stay 🏠

> Revolutionizing vacation rentals with Web3 privacy and verification technology

## Problem Statement
Ever felt deceived by the difference between listed and final prices on vacation rental platforms? Name a Stay tackles this transparency issue while revolutionizing how rental data is verified and shared, putting control back in users' hands through Web3 technology.

## Key Features
- 🔐 Zero-knowledge proof verification of Airbnb data
- 🤖 AI-powered travel assistant chatbot
- 💫 One-click checkout using Web3Auth
- 🔒 Privacy-preserving guest verification
- 📊 Transparent pricing and review system

## Technology Stack
This project combines cutting-edge Web3 technologies:

### Zero-Knowledge Proofs (vLayer)
- **Base Network (Web Proof)**
  - Web Prover: [`0xd8D0...5f83`](https://base-sepolia.blockscout.com/address/0xd8D0118c77A262227D7E77DE56E3d9Aa19035f83)
  - Web Verifier: [`0xD20D...6aE`](https://base-sepolia.blockscout.com/address/0xD20DaeFdF8dD24d07C0ad6F566b3DD492850F6aE)

- **Scroll Network (Email Proof)**
  - Email Prover: [`0xb087...434`](https://sepolia.scrollscan.com/address/0xb087c13f03b0b5a303d919cbf4d732b835afe434)
  - Email Verifier: [`0xec83...1ed`](https://sepolia.scrollscan.com/address/0xec83726d319598c2b33046f36b63fe29334201ed)

### Privacy & Security
- **FHE (Fhenix)**: Private storage and verification of guest data
- **MPC (Web3Auth)**: Seamless one-click authentication
- **TEE (Lit Protocol)**: Secure AI model execution via Claircent

## Project Structure
├── index.html          # Main UI interface
├── contracts/
│   ├── base/          # vLayer web proof contracts
│   ├── scroll/        # vLayer email proof contracts
│   └── fhenix/        # Privacy-preserving security deposit contracts

## How It Works
1. **Data Verification**: Users can verify their Airbnb data through:
   - Web proofs on Base network (review verification)
   - Email proofs on Scroll network (comprehensive dataset)

2. **Privacy Preservation**: 
   - Guest data is stored privately using Fhenix
   - Hosts can verify guest requirements without accessing sensitive data

3. **Seamless Experience**:
   - One-click checkout through Web3Auth
   - AI chatbot assistance for travel needs
   - Transparent pricing and verification

## Innovation Highlights
- **Data Ownership**: Users can verify and control their Airbnb data without platform dependency
- **Privacy First**: FHE enables secure verification without exposing sensitive information
- **Seamless UX**: Combines Web3 security with Web2-like user experience

## Future Developments
- Integration of additional vacation rental platforms
- Enhanced AI travel assistance features
- Expanded privacy-preserving verification methods

## Contributing
We welcome contributions! Please feel free to submit pull requests or open issues for discussion.

## License
[Add your license information here]
