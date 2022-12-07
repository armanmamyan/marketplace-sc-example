// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ERC1155Tradable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract Marketplace is
    ERC1155Receiver,
    IERC721Receiver,
    ReentrancyGuard,
    Ownable
{
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    Counters.Counter private _createdTokenIds;
    Counters.Counter private _offeringIds;
    Counters.Counter private _itemsSold;
    address private operator;
    address private mkNFTaddress;
    address private serviceWallet = owner();

    ERC1155Tradable mkNFT;

    uint256 public serviceFee = 25 * 10 ** 17; // 2.5 %
    uint256 constant ROYALTY_MAX = 100 * 10 ** 18; // 10%

    constructor(
        address _nftAddress,
        address _operator,
        address _serviceWallet
    ) {
        mkNFTaddress = _nftAddress;
        operator = _operator;
        serviceWallet = _serviceWallet;
        mkNFT = ERC1155Tradable(_nftAddress);
    }

    /**  STRUCT START */
    struct CreateToken {
        address nftContract;
        uint256 tokenId;
        address owner;
        uint256 price;
        address RoyaltyAddress;
        uint RoyaltyPercentage;
        uint startDate;
        uint endDate;
        bool currentlyListed;
        bool createdByMarketpalce;
    }

    struct CreateOffering {
        uint nonce;
        bytes32 generatedABI;
        address offerer; // Oferrer
        address nftAddress; // Address of the NFT Collection contract
        uint256 tokenId;
        uint256 bidPrice; // Current highest bid for the auction
        uint startBlock; // Start block is always the time of bidding
        uint endBlock;
    }

    /**  STRUCT END */

    /**  EVENTS START */
    event ItemListed(
        address indexed owner,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 price
    );

    event ItemCanceled(
        address indexed owner,
        address indexed nftAddress,
        uint256 indexed tokenId
    );

    event ItemBought(
        address indexed buyer,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 price
    );
    event OfferingPlaced(
        bytes32 indexed offeringId,
        address indexed nftAddress,
        address indexed offerer,
        uint256 tokenId,
        uint price,
        uint256 startBlock,
        uint256 endBlock
    );
    event SetNFTAddress(address _sender, address _nftAddress);
    event OfferingCancelled(uint indexed _nonce);
    event OfferingClosed(uint indexed _nonce, address indexed _buyer);
    event ServiceFeeUpdated(uint256 _feePrice);
    event SetOperator(address _operatorAddress);
    event TokenCreated(
        string _tokenURI,
        uint256 _tokenId,
        address _ownerAddress
    );
    event TokenOfferingsRemovedFor(address _tokenAddress, uint256 _tokenId);
    event TokenTransfered(uint256 _tokenId, address _from, address _to);
    /**  EVENTS START */

    /**  MAPPING START */
    //This mapping maps tokenId to token info and is helpful when retrieving details about a tokenId
    mapping(uint256 => CreateToken) private idToListedToken;
    mapping(bytes32 => CreateOffering) private offeringRegistry;
    mapping(uint256 => CreateOffering) private offerersData;
    /**  MAPPING END */

    /**  MODIFIERS END */
    modifier notListed(
        address nftAddress,
        uint256 tokenId,
        address owner
    ) {
        require(
            !idToListedToken[tokenId].currentlyListed,
            "Token is already listed"
        );
        _;
    }

    modifier isListed(address nftAddress, uint256 tokenId) {
        require(
            idToListedToken[tokenId].currentlyListed,
            "Can not proceed: Token is not listed"
        );
        _;
    }

    modifier onlyOperator() {
        require(
            msg.sender == operator,
            "Only operator is able to use the method"
        );
        _;
    }

    /**  MODIFIERS END */

    function updateServiceFee(uint256 _feePrice) external onlyOwner {
        serviceFee = _feePrice;
        emit ServiceFeeUpdated(_feePrice);
    }

    function setOperator(address _operatorAddress) external onlyOwner {
        operator = _operatorAddress;
        emit SetOperator(_operatorAddress);
    }

    //The first time a token is created, it is listed here
    function createToken(string memory _tokenURI) public returns (uint) {
        //Increment the tokenId counter, which is keeping track of the number of minted NFTs
        _createdTokenIds.increment();
        uint256 tokenID = _createdTokenIds.current();
        // Calling to Tradable Contract to create the token
        uint256 currentTokenId = mkNFT.create(
            msg.sender,
            tokenID,
            1,
            _tokenURI,
            ""
        );
        emit TokenCreated(_tokenURI, currentTokenId, msg.sender);
        return currentTokenId;
    }

    function listItem(
        address nftAddress,
        uint256 tokenId,
        uint256 price,
        address royaltyAddress,
        uint256 royaltyPercentage,
        uint startDate,
        uint endDate
    ) external nonReentrant {
        require(
            startDate <= endDate,
            "End Date can not be smaller or equal to now"
        );

        IERC1155 nft = IERC1155(nftAddress);
        if (nft.supportsInterface(0xd9b67a26) == true) {
            require(
                nft.isApprovedForAll(msg.sender, address(this)),
                "NFT is not approved for sale"
            );
        }

        IERC721 nft721 = IERC721(nftAddress);
        if (nft721.supportsInterface(0x80ac58cd) == true) {
            require(
                nft.isApprovedForAll(msg.sender, address(this)),
                "NFT is not approved for sale"
            );
        }

        _tokenIds.increment();
        uint256 currentTokenID = _tokenIds.current();

        idToListedToken[currentTokenID] = CreateToken(
            nftAddress,
            tokenId,
            payable(msg.sender),
            price,
            royaltyAddress,
            royaltyPercentage,
            startDate,
            endDate,
            true,
            false
        );

        emit ItemListed(msg.sender, nftAddress, tokenId, price);
    }

    function executeSale(
        address _nftAddress,
        uint256 _tokenId
    ) external payable isListed(_nftAddress, _tokenId) nonReentrant {
        require(
            block.timestamp < idToListedToken[_tokenId].endDate,
            "Listing has ended"
        );
        require(msg.value > idToListedToken[_tokenId].price, "Price not met");

        _customTransfer(
            idToListedToken[_tokenId].owner,
            msg.sender,
            _nftAddress,
            _tokenId
        );

        _itemsSold.increment();
        uint256 fee;
        uint256 userReceipt = 0;

        if (serviceFee > 0 && serviceWallet != address(0)) {
            fee = (msg.value * serviceFee) / ROYALTY_MAX;
            userReceipt += fee;
            (bool success, ) = payable(serviceWallet).call{value: fee}("");
            require(success, "Transfer failed.");
        }

        if (
            idToListedToken[_tokenId].RoyaltyPercentage > 0 &&
            idToListedToken[_tokenId].RoyaltyAddress != address(0)
        ) {
            fee =
                (msg.value * idToListedToken[_tokenId].RoyaltyPercentage) /
                ROYALTY_MAX;
            if (fee > 0) {
                userReceipt += fee;
                (bool isRoyaltySent, ) = payable(
                    idToListedToken[_tokenId].RoyaltyAddress
                ).call{value: fee}("");
                require(isRoyaltySent, "Transfer failed.");
            }
        }

        require(msg.value >= userReceipt, "invalid royalty or service fee");
        userReceipt = msg.value - userReceipt;

        if (userReceipt > 0) {
            (bool isSuccess, ) = payable(idToListedToken[_tokenId].owner).call{
                value: userReceipt
            }("");
            require(isSuccess, "Transfer failed.");
        }

        _removeTokenOfferings(_nftAddress, _tokenId);

        _tokenIds.decrement();
        delete (idToListedToken[_tokenId]);
        emit ItemBought(
            msg.sender,
            _nftAddress,
            _tokenId,
            idToListedToken[_tokenId].price
        );
    }

    function operatorCancellation(
        address _nftAddress,
        uint256 _tokenId
    ) external isListed(_nftAddress, _tokenId) onlyOperator nonReentrant {
        _removeTokenOfferings(_nftAddress, _tokenId);
        _tokenIds.decrement();
        delete (idToListedToken[_tokenId]);
        emit ItemCanceled(msg.sender, _nftAddress, _tokenId);
    }

    function cancelListing(
        address _nftAddress,
        uint256 _tokenId
    ) external isListed(_nftAddress, _tokenId) {
        _removeTokenOfferings(_nftAddress, _tokenId);
        _tokenIds.decrement();
        delete (idToListedToken[_tokenId]);
        emit ItemCanceled(msg.sender, _nftAddress, _tokenId);
    }

    function updateListing(
        address _nftAddress,
        uint256 _tokenId,
        uint256 newPrice
    ) external isListed(_nftAddress, _tokenId) nonReentrant {
        require(newPrice >= 0, "Price must be equal or above zero");

        idToListedToken[_tokenId].price = newPrice;
        emit ItemListed(msg.sender, _nftAddress, _tokenId, newPrice);
    }

    function getNFTOfferings(
        address _nftAddress,
        uint _tokenId
    ) public view returns (CreateOffering[] memory) {
        uint totalOffersCount = _offeringIds.current();
        uint itemCount = 0;
        uint currentIndex = 0;

        for (uint i = 0; i < totalOffersCount; i++) {
            if (
                offerersData[i + 1].nftAddress == _nftAddress &&
                offerersData[i + 1].tokenId == _tokenId
            ) {
                itemCount += 1;
            }
        }

        // Once have the count of relevant NFTs, create an array then store all the NFts in it
        CreateOffering[] memory items = new CreateOffering[](itemCount);
        for (uint i = 0; i < totalOffersCount; i++) {
            if (
                offerersData[i + 1].nftAddress == _nftAddress &&
                offerersData[i + 1].tokenId == _tokenId
            ) {
                uint currentId = i + 1;
                CreateOffering storage currentItem = offerersData[currentId];
                items[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }
        return items;
    }

    function _removeTokenOfferings(
        address _nftAddress,
        uint256 _tokenId
    ) private returns (bool success) {
        // Removing all existed offers
        for (uint i = 0; i < _offeringIds.current(); i++) {
            if (
                offerersData[i + 1].nftAddress == _nftAddress &&
                offerersData[i + 1].tokenId == _tokenId
            ) {
                uint currentId = i + 1;
                CreateOffering storage currentItem = offerersData[currentId];
                delete (offeringRegistry[currentItem.generatedABI]);
            }
        }
        emit TokenOfferingsRemovedFor(_nftAddress, _tokenId);
        return true;
    }

    function _customTransfer(
        address _sender,
        address _receiver,
        address _nftAddress,
        uint256 _tokenId
    ) private returns (bool success) {
        // Get NFT collection contract
        IERC1155 nft = IERC1155(_nftAddress);
        if (nft.supportsInterface(0xd9b67a26) == true) {
            require(
                nft.balanceOf(_sender, _tokenId) != 0,
                "Caller is not the owner of the NFT"
            );
            nft.safeTransferFrom(_sender, _receiver, _tokenId, 1, "");
            emit TokenTransfered(_tokenId, _sender, _receiver);
            return true;
        }

        IERC721 nft721 = IERC721(_nftAddress);
        if (nft721.supportsInterface(0x80ac58cd) == true) {
            // Make sure the sender that wants to create a new auction
            // for a specific NFT is the owner of this NFT
            require(
                nft721.ownerOf(_tokenId) == _sender,
                "Caller is not the owner of the NFT"
            );
            nft721.safeTransferFrom(_sender, _receiver, _tokenId);
            emit TokenTransfered(_tokenId, _sender, _receiver);
            return true;
        }
    }

    function placeOffer(
        address nftAddress,
        uint tokenId,
        uint price,
        uint startBlock,
        uint endBlock
    ) external payable nonReentrant returns (bool success) {
        require(
            idToListedToken[tokenId].currentlyListed,
            "The offer is not allowed for not listed items"
        );

        require(
            startBlock <= endBlock,
            "Offering Time Must be greater than NOW"
        );

        _offeringIds.increment();
        uint256 nonce = _offeringIds.current();
        bytes32 generatedABI = keccak256(
            abi.encodePacked(nonce, nftAddress, tokenId)
        );

        offerersData[nonce] = CreateOffering(
            nonce,
            generatedABI,
            msg.sender,
            nftAddress,
            tokenId,
            price,
            startBlock,
            endBlock
        );

        emit OfferingPlaced(
            generatedABI,
            nftAddress,
            msg.sender,
            tokenId,
            price,
            startBlock,
            endBlock
        );

        return true;
    }

    function cancelOffer(uint _nonce) external nonReentrant {
        require(
            msg.sender == offerersData[_nonce].offerer,
            "You are not allowed to cancel the offer"
        );
        delete (offerersData[_nonce]);
        emit OfferingCancelled(_nonce);
    }

    function operatorCancelOffer(
        uint _nonce
    ) external onlyOperator nonReentrant {
        delete (offerersData[_nonce]);
        emit OfferingCancelled(_nonce);
    }

    function acceptOffer(uint _nonce, address _token) external nonReentrant {
        CreateOffering storage currentOffer = offerersData[_nonce];

        require(
            idToListedToken[currentOffer.tokenId].currentlyListed,
            "Item already has been bought"
        );
        require(block.timestamp < currentOffer.endBlock, "Offer Time Exceeds");
        require(
            idToListedToken[currentOffer.tokenId].owner == msg.sender,
            "Only owner of the NFT can accept the offer"
        );

        _customTransfer(
            msg.sender,
            currentOffer.offerer,
            currentOffer.nftAddress,
            currentOffer.tokenId
        );

        uint256 fee;
        uint256 userReceipt = 0;
        IERC20 token = IERC20(_token);

        if (serviceFee > 0 && serviceWallet != address(0)) {
            fee = (currentOffer.bidPrice * serviceFee) / ROYALTY_MAX;
            userReceipt += fee;
            bool isSuccess = token.transferFrom(
                payable(currentOffer.offerer),
                serviceWallet,
                fee
            );
            require(isSuccess, "Transfer failed");
        }

        if (
            idToListedToken[currentOffer.tokenId].RoyaltyPercentage > 0 &&
            idToListedToken[currentOffer.tokenId].RoyaltyAddress != address(0)
        ) {
            fee =
                (currentOffer.bidPrice *
                    idToListedToken[currentOffer.tokenId].RoyaltyPercentage) /
                ROYALTY_MAX;
            if (fee > 0) {
                userReceipt += fee;
                bool isSuccess = token.transferFrom(
                    payable(currentOffer.offerer),
                    payable(
                        idToListedToken[currentOffer.tokenId].RoyaltyAddress
                    ),
                    fee
                );
                require(isSuccess, "Transfer failed");
            }
        }

        require(
            currentOffer.bidPrice >= userReceipt,
            "invalid royalty or service fee"
        );
        userReceipt = currentOffer.bidPrice - userReceipt;

        if (userReceipt > 0) {
            token.transferFrom(
                payable(currentOffer.offerer),
                payable(msg.sender),
                userReceipt
            );
        }

        _removeTokenOfferings(currentOffer.nftAddress, currentOffer.tokenId);
        delete (idToListedToken[currentOffer.tokenId]);
        emit OfferingClosed(_nonce, msg.sender);
    }

    function withDraw(uint256 _amount) external onlyOwner {
        require(_amount > 0, "Invalid withdraw amount...");
        require(address(this).balance > _amount, "None left to withdraw...");

        (bool isSuccess, ) = payable(msg.sender).call{value: _amount}("");
        require(isSuccess, "Withdraw failed.");
    }

    function withDrawAll() external onlyOwner {
        uint256 remaining = address(this).balance;
        require(remaining > 0, "None left to withdraw...");

        (bool isSuccess, ) = payable(msg.sender).call{value: remaining}("");
        require(isSuccess, "Withdraw failed.");
    }

    receive() external payable {}

    fallback() external payable {}

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public pure virtual returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public virtual returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
