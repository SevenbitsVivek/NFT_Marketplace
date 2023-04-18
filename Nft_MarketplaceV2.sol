//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

contract Nft_Marketplace is ERC721, IERC721Receiver, Ownable, ReentrancyGuard{
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter;

    constructor() ERC721("MyNft", "NFT") {}

    struct SellNft {
        address nftOwner;
        uint256 price;
        bool isNftOnSale;
    }

    struct AuctionNft {
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
    
    mapping(uint256 => SellNft) private sellNft;
    mapping(uint256 => AuctionNft) private auctionNft;
    mapping(address => mapping(uint256 => bool)) private isBidded;

    event NftSold(address _nftOwner, uint256 indexed _tokenId, uint256 indexed _price, bool isNftOnSale);
    event NftBought(uint256 indexed _tokenId, address _nftOwner, uint256 indexed _BoughtPrice);
    event NftOnAuction(address _nftOwner, uint256 indexed _tokenId, uint256 indexed _basePrice, uint256 _startTime, uint256 _endTime, bool isNftOnAuction);
    event NftBidded(uint256 indexed _tokenId, address _bidder, uint256 indexed _bidAmount, uint256 _startTime, uint256 _endTime);

    function safeMint(address to) public {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
    }

    function sellNFT(uint256 _tokenId, uint256 _price) external nonReentrant {
        require(_price > 0, "Price cannot be 0");
        require(ownerOf(_tokenId) == msg.sender, "Invalid owner of the nft");
        require(!auctionNft[_tokenId].isNftOnAuction, "Already on auction");
        require(!sellNft[_tokenId].isNftOnSale, "Already on sale");
        require(getApproved(_tokenId) == address(this), "Check the nft allowance");
        sellNft[_tokenId].price = _price;
        sellNft[_tokenId].nftOwner = ownerOf(_tokenId);
        sellNft[_tokenId].isNftOnSale = true;
        safeTransferFrom(msg.sender, address(this), _tokenId);
        emit NftSold(msg.sender, _tokenId, _price, sellNft[_tokenId].isNftOnSale);
    }

    function buyNFT(uint256 _tokenId) external payable {
        require(msg.value > 0, "Price cannot be 0");
        require(sellNft[_tokenId].isNftOnSale, "Not on sale");
        require(msg.value == sellNft[_tokenId].price, "Invalid price");
        sellNft[_tokenId].isNftOnSale = false;
        sellNft[_tokenId].price = 0;
        payable(sellNft[_tokenId].nftOwner).transfer(msg.value);
        _transfer(address(this), msg.sender, _tokenId);
        sellNft[_tokenId].nftOwner = msg.sender;
        emit NftBought(_tokenId, msg.sender, msg.value);
    }

    function sellNFTOnAuction(uint256 _tokenId, uint256 _basePrice, uint256 _startTime, uint256 _endTime) external nonReentrant {
        require(_basePrice > 0, "Price cannot be 0");
        require(ownerOf(_tokenId) == msg.sender, "Invalid owner of the nft");
        require(!sellNft[_tokenId].isNftOnSale, "Nft on sale");
        require(getApproved(_tokenId) == address(this), "Check the nft allowance");
        require(!auctionNft[_tokenId].isNftOnAuction, "Already on auction");
        auctionNft[_tokenId].isNftOnAuction = true;
        auctionNft[_tokenId].nftOwner = msg.sender;
        auctionNft[_tokenId].basePrice = _basePrice;
        auctionNft[_tokenId].startTime = _startTime + block.timestamp;
        auctionNft[_tokenId].endTime = auctionNft[_tokenId].startTime + _endTime;
        safeTransferFrom(msg.sender, address(this), _tokenId);
        emit NftOnAuction(msg.sender, _tokenId, _basePrice, _startTime, _endTime,  auctionNft[_tokenId].isNftOnAuction);
    }

    function bidNFT(uint256 _tokenId) external payable nonReentrant {
        require(msg.value > 0, "Value cannot be 0");
        require(auctionNft[_tokenId].isNftOnAuction, "Nft not on auction");
        require(block.timestamp >= auctionNft[_tokenId].startTime, "Auction not started yet");
        require(msg.value >= auctionNft[_tokenId].basePrice, "Invalid basePrice");
        require(block.timestamp <= auctionNft[_tokenId].endTime, "Auction time ended");
        require(!auctionNft[_tokenId].isAuctionEnded, "Auction ended");
        uint256 previousHighestBid = auctionNft[_tokenId].highestBid;
        require(msg.value > previousHighestBid, "Invalid previousHighestBid");
        address previousHighestBidder = auctionNft[_tokenId].highestBidder;
        if (msg.value > previousHighestBid) {
            if(!isBidded[msg.sender][_tokenId]) {
                isBidded[msg.sender][_tokenId] = true;
            }
            // Refund previous highest bidder
            if (previousHighestBidder != address(0) && previousHighestBid != 0) {
                require(address(this).balance >= previousHighestBid, "Not enough balance");
                payable(previousHighestBidder).transfer(previousHighestBid);
            }
            // Update auction information with new highest bidder and bid
            auctionNft[_tokenId].highestBidder = msg.sender;
            auctionNft[_tokenId].highestBid = msg.value;
            auctionNft[_tokenId].tokenId = _tokenId;
            emit NftBidded(_tokenId, msg.sender, msg.value, block.timestamp, auctionNft[_tokenId].endTime);
        }
    }

    function endAuction(uint256 _tokenId) external nonReentrant {
        require(auctionNft[_tokenId].nftOwner == msg.sender, "Invalid nft owner");
        require(auctionNft[_tokenId].isNftOnAuction, "Nft not on auction");
        require(block.timestamp >= auctionNft[_tokenId].startTime, "Auction not started yet");
        require(!auctionNft[_tokenId].isAuctionEnded, "Auction already ended");
        require(auctionNft[_tokenId].highestBid != 0, "Highest bid canot be 0");
        payable(auctionNft[_tokenId].nftOwner).transfer(auctionNft[_tokenId].highestBid);
        auctionNft[_tokenId].isAuctionEnded = true;
        auctionNft[_tokenId].isNftOnAuction = false;
        auctionNft[_tokenId].basePrice = 0;
        auctionNft[_tokenId].canClaim = true;
    }

    function claimNFT(uint256 _tokenId) external nonReentrant {
        require(auctionNft[_tokenId].canClaim, "Cannot claim");
        require(auctionNft[_tokenId].highestBidder == msg.sender, "Invalid highest bidder");
        require(auctionNft[_tokenId].tokenId == _tokenId, "Invalid tokenId");
        auctionNft[_tokenId].isAuctionEnded = false;
        delete auctionNft[_tokenId].highestBidder;
        _transfer(address(this), msg.sender, _tokenId);
        auctionNft[_tokenId].highestBid = 0;
        auctionNft[_tokenId].canClaim = false;
        auctionNft[_tokenId].nftOwner = msg.sender;
    }

    function setNFTSellPrice(uint256 _tokenId, uint256 _newPrice) external {
        require(_newPrice > 0, "Invalid price");
        require(sellNft[_tokenId].nftOwner == msg.sender, "Invalid nft owner");
        require(sellNft[_tokenId].isNftOnSale, "Not on sale");
        require( sellNft[_tokenId].price != _newPrice, "Price is already same");
        sellNft[_tokenId].price = _newPrice;
    }

    function setNFTAuctionBasePrice(uint256 _tokenId, uint256 _newBasePrice) external {
        require(_newBasePrice > 0, "Invalid price");
        require(auctionNft[_tokenId].nftOwner == msg.sender, "Invalid nft owner");
        require(auctionNft[_tokenId].isNftOnAuction, "Nft not on auction");
        require(block.timestamp >= auctionNft[_tokenId].startTime, "Auction no started yet");
        require(auctionNft[_tokenId].basePrice != _newBasePrice, "BasePrice is already same");
        auctionNft[_tokenId].basePrice = _newBasePrice;
    }

    function withdraw(address payable recipient) external onlyOwner {
        require(recipient != address(0), "Address cannot be zero");
        recipient.transfer(address(this).balance);
    }

    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function getNFTSellInfo(uint256 _tokenId) external view returns (SellNft memory) {
        return sellNft[_tokenId];
    }

    function getNFTAuctionInfo(uint256 _tokenId) external view returns (AuctionNft memory) {
        return auctionNft[_tokenId];
    }
}
