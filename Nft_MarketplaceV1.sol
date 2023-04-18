//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

contract Nft_Marketplace is IERC721Receiver, Ownable, ReentrancyGuard{

    constructor() {}

    struct SellNft {
        address nftTokenAddress;
        address nftOwner;
        uint256 price;
        bool isNftOnSale;
    }

    struct AuctionNft {
        address nftTokenAddress;
        address nftOwner;
        uint256 tokenId;
        uint256 basePrice;
        bool isNftOnAuction;
        bool isAuctionEnded;
        bool canClaim;
        uint256 startTime;
        uint256 endTime;
        address highestBidder;
        uint256 highestBid;
    }
    
    mapping(IERC721 => mapping(uint256 => SellNft)) private sellNft;
    mapping(IERC721 => mapping(uint256 => AuctionNft)) private auctionNft;
    mapping(IERC721 => mapping(uint256 => address [])) private biddersList;
    mapping(IERC721 => mapping(address => mapping(uint256 => bool))) private isBidded;

    event NftSold(address indexed _nftTokenAddress, address _nftOwner, uint256 indexed _tokenId, uint256 indexed _price, bool isNftOnSale);
    event NftBought(address indexed _nftTokenAddress, uint256 indexed _tokenId, address _nftOwner, uint256 indexed _BoughtPrice);
    event NftOnAuction(address indexed _nftTokenAddress, address _nftOwner, uint256 indexed _tokenId, uint256 indexed _basePrice, uint256 _startTime, uint256 _endTime, bool isNftOnAuction);
    event NftBidded(address indexed _nftTokenAddress, uint256 indexed _tokenId, address _bidder, uint256 indexed _bidAmount, uint256 _startTime, uint256 _endTime);

    function sellNFT(address _nftTokenAddress, uint256 _tokenId, uint256 _price) external nonReentrant {
        require(_nftTokenAddress != address(0), "Address cannot be 0");
        require(_price > 0, "Price cannot be 0");
        require(IERC721(_nftTokenAddress).ownerOf(_tokenId) == msg.sender, "Invalid owner of the nft");
        require(!auctionNft[IERC721(_nftTokenAddress)][_tokenId].isNftOnAuction, "Already on auction");
        require(!sellNft[IERC721(_nftTokenAddress)][_tokenId].isNftOnSale, "Already on sale");
        require(IERC721(_nftTokenAddress).getApproved(_tokenId) == address(this), "Check the nft allowance");
        sellNft[IERC721(_nftTokenAddress)][_tokenId].nftTokenAddress = _nftTokenAddress;
        sellNft[IERC721(_nftTokenAddress)][_tokenId].price = _price;
        sellNft[IERC721(_nftTokenAddress)][_tokenId].nftOwner = IERC721(_nftTokenAddress).ownerOf(_tokenId);
        sellNft[IERC721(_nftTokenAddress)][_tokenId].isNftOnSale = true;
        IERC721(_nftTokenAddress).safeTransferFrom(msg.sender, address(this), _tokenId);
        emit NftSold(_nftTokenAddress, msg.sender, _tokenId, _price, sellNft[IERC721(_nftTokenAddress)][_tokenId].isNftOnSale);
    }

    function buyNFT(address _nftTokenAddress, uint256 _tokenId) external payable {
        require(_nftTokenAddress != address(0), "Address cannot be 0");
        require(msg.value > 0, "Price cannot be 0");
        require(sellNft[IERC721(_nftTokenAddress)][_tokenId].isNftOnSale, "Not on sale");
        require(msg.value == sellNft[IERC721(_nftTokenAddress)][_tokenId].price, "Invalid price");
        sellNft[IERC721(_nftTokenAddress)][_tokenId].isNftOnSale = false;
        sellNft[IERC721(_nftTokenAddress)][_tokenId].price = 0;
        payable(sellNft[IERC721(_nftTokenAddress)][_tokenId].nftOwner).transfer(msg.value);
        IERC721(_nftTokenAddress).safeTransferFrom(address(this), msg.sender, _tokenId);
        sellNft[IERC721(_nftTokenAddress)][_tokenId].nftOwner = msg.sender;
        emit NftBought(_nftTokenAddress, _tokenId, msg.sender, msg.value);
    }

    function sellNFTOnAuction(address _nftTokenAddress, uint256 _tokenId, uint256 _basePrice, uint256 _startTime, uint256 _endTime) external nonReentrant {
        require(_nftTokenAddress != address(0), "Address cannot be 0");
        require(_basePrice > 0, "Price cannot be 0");
        require(IERC721(_nftTokenAddress).ownerOf(_tokenId) == msg.sender, "Invalid owner of the nft");
        require(!sellNft[IERC721(_nftTokenAddress)][_tokenId].isNftOnSale, "Nft on sale");
        require(IERC721(_nftTokenAddress).getApproved(_tokenId) == address(this), "Check the nft allowance");
        require(!auctionNft[IERC721(_nftTokenAddress)][_tokenId].isNftOnAuction, "Already on auction");
        auctionNft[IERC721(_nftTokenAddress)][_tokenId].isNftOnAuction = true;
        auctionNft[IERC721(_nftTokenAddress)][_tokenId].nftTokenAddress = _nftTokenAddress;
        auctionNft[IERC721(_nftTokenAddress)][_tokenId].nftOwner = msg.sender;
        auctionNft[IERC721(_nftTokenAddress)][_tokenId].basePrice = _basePrice;
        auctionNft[IERC721(_nftTokenAddress)][_tokenId].startTime = _startTime + block.timestamp;
        auctionNft[IERC721(_nftTokenAddress)][_tokenId].endTime = auctionNft[IERC721(_nftTokenAddress)][_tokenId].startTime + _endTime;
        IERC721(_nftTokenAddress).safeTransferFrom(msg.sender, address(this), _tokenId);
        emit NftOnAuction(_nftTokenAddress, msg.sender, _tokenId, _basePrice, _startTime, _endTime,  auctionNft[IERC721(_nftTokenAddress)][_tokenId].isNftOnAuction);
    }

    function bidNFT(address _nftTokenAddress, uint256 _tokenId) external payable nonReentrant {
        require(_nftTokenAddress != address(0), "Address cannot be 0");
        require(msg.value > 0, "Value cannot be 0");
        require(auctionNft[IERC721(_nftTokenAddress)][_tokenId].isNftOnAuction, "Nft not on auction");
        require(block.timestamp >= auctionNft[IERC721(_nftTokenAddress)][_tokenId].startTime, "Auction not started yet");
        require(msg.value >= auctionNft[IERC721(_nftTokenAddress)][_tokenId].basePrice, "Invalid basePrice");
        require(block.timestamp <= auctionNft[IERC721(_nftTokenAddress)][_tokenId].endTime, "Auction time ended");
        require(!auctionNft[IERC721(_nftTokenAddress)][_tokenId].isAuctionEnded, "Auction ended");
        uint256 previousHighestBid = auctionNft[IERC721(_nftTokenAddress)][_tokenId].highestBid;
        require(msg.value > previousHighestBid, "Invalid previousHighestBid");
        address previousHighestBidder = auctionNft[IERC721(_nftTokenAddress)][_tokenId].highestBidder;
        if (msg.value > previousHighestBid) {
            if(!isBidded[IERC721(_nftTokenAddress)][msg.sender][_tokenId]) {
                isBidded[IERC721(_nftTokenAddress)][msg.sender][_tokenId] = true;
                biddersList[IERC721(_nftTokenAddress)][_tokenId].push(msg.sender);
            }
            // Refund previous highest bidder
            if (previousHighestBidder != address(0) && previousHighestBid != 0) {
                require(address(this).balance >= previousHighestBid, "Not enough balance");
                payable(previousHighestBidder).transfer(previousHighestBid);
            }
            // Update auction information with new highest bidder and bid
            auctionNft[IERC721(_nftTokenAddress)][_tokenId].highestBidder = msg.sender;
            auctionNft[IERC721(_nftTokenAddress)][_tokenId].highestBid = msg.value;
            auctionNft[IERC721(_nftTokenAddress)][_tokenId].tokenId = _tokenId;
            emit NftBidded(_nftTokenAddress, _tokenId, msg.sender, msg.value, block.timestamp, auctionNft[IERC721(_nftTokenAddress)][_tokenId].endTime);
        }
    }

    function endAuction(address _nftTokenAddress, uint256 _tokenId) external nonReentrant {
        require(_nftTokenAddress != address(0), "Address cannot be 0");
        require(auctionNft[IERC721(_nftTokenAddress)][_tokenId].nftOwner == msg.sender, "Invalid nft owner");
        require(auctionNft[IERC721(_nftTokenAddress)][_tokenId].isNftOnAuction, "Nft not on auction");
        require(block.timestamp >= auctionNft[IERC721(_nftTokenAddress)][_tokenId].startTime, "Auction not started yet");
        require(!auctionNft[IERC721(_nftTokenAddress)][_tokenId].isAuctionEnded, "Auction already ended");
        require(auctionNft[IERC721(_nftTokenAddress)][_tokenId].highestBid != 0, "Highest bid cannot be 0");
        payable(auctionNft[IERC721(_nftTokenAddress)][_tokenId].nftOwner).transfer(auctionNft[IERC721(_nftTokenAddress)][_tokenId].highestBid);
        auctionNft[IERC721(_nftTokenAddress)][_tokenId].isAuctionEnded = true;
        auctionNft[IERC721(_nftTokenAddress)][_tokenId].isNftOnAuction = false;
        auctionNft[IERC721(_nftTokenAddress)][_tokenId].basePrice = 0;
        delete biddersList[IERC721(_nftTokenAddress)][_tokenId];
        auctionNft[IERC721(_nftTokenAddress)][_tokenId].canClaim = true;
    }

    function claimNFT(address _nftTokenAddress, uint256 _tokenId) external nonReentrant {
        require(_nftTokenAddress != address(0), "Address cannot be 0");
        require(auctionNft[IERC721(_nftTokenAddress)][_tokenId].highestBidder == msg.sender, "Invalid bidder");
        require(auctionNft[IERC721(_nftTokenAddress)][_tokenId].canClaim, "Nft cannot claim");
        require(auctionNft[IERC721(_nftTokenAddress)][_tokenId].tokenId == _tokenId, "Invalid tokenId to claim");
        auctionNft[IERC721(_nftTokenAddress)][_tokenId].isAuctionEnded = false;
        delete auctionNft[IERC721(_nftTokenAddress)][_tokenId].highestBidder;
        IERC721(_nftTokenAddress).safeTransferFrom(address(this), msg.sender, _tokenId);
        auctionNft[IERC721(_nftTokenAddress)][_tokenId].highestBid = 0;
        auctionNft[IERC721(_nftTokenAddress)][_tokenId].canClaim = false;
        auctionNft[IERC721(_nftTokenAddress)][_tokenId].nftOwner = msg.sender;
    }

    function setNFTSellPrice(address _nftTokenAddress, uint256 _tokenId, uint256 _newPrice) external {
        require(_nftTokenAddress != address(0), "Address cannot be 0");
        require(_newPrice > 0, "Invalid price");
        require(sellNft[IERC721(_nftTokenAddress)][_tokenId].nftOwner == msg.sender, "Invalid nft owner");
        require(sellNft[IERC721(_nftTokenAddress)][_tokenId].isNftOnSale, "Not on sale");
        require( sellNft[IERC721(_nftTokenAddress)][_tokenId].price != _newPrice, "Price is already same");
        sellNft[IERC721(_nftTokenAddress)][_tokenId].price = _newPrice;
    }

    function setNFTAuctionBasePrice(address _nftTokenAddress, uint256 _tokenId, uint256 _newBasePrice) external {
        require(_nftTokenAddress != address(0), "Address cannot be 0");
        require(_newBasePrice > 0, "Invalid price");
        require(auctionNft[IERC721(_nftTokenAddress)][_tokenId].nftOwner == msg.sender, "Invalid nft owner");
        require(auctionNft[IERC721(_nftTokenAddress)][_tokenId].isNftOnAuction, "Nft not on auction");
        require(block.timestamp >= auctionNft[IERC721(_nftTokenAddress)][_tokenId].startTime, "Auction no started yet");
        require(auctionNft[IERC721(_nftTokenAddress)][_tokenId].basePrice != _newBasePrice, "BasePrice is already same");
        auctionNft[IERC721(_nftTokenAddress)][_tokenId].basePrice = _newBasePrice;
    }

    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function getNFTSellInfo(address _nftTokenAddress, uint256 _tokenId) external view returns (SellNft memory) {
        return sellNft[IERC721(_nftTokenAddress)][_tokenId];
    }

    function getNFTAuctionInfo(address _nftTokenAddress, uint256 _tokenId) external view returns (AuctionNft memory) {
        return auctionNft[IERC721(_nftTokenAddress)][_tokenId];
    }

    function getBiddersList(address _nftTokenAddress, uint256 _tokenId) external view returns (address [] memory) {
        return biddersList[IERC721(_nftTokenAddress)][_tokenId];
    }
}
