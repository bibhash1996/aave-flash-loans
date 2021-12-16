pragma solidity ^0.6.6;

import "./aave/FlashLoanReceiverBase.sol";
import "./aave/ILendingPoolAddressesProvider.sol";
import "./aave/ILendingPool.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract Flashloan is FlashLoanReceiverBase {
    address internal constant UNISWAP_ROUTER_ADDRESS =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    //Uniswap V2 router
    IUniswapV2Router02 public uniswapRouter;

    // DAI Token address on the Kovan testnet
    address private constant DAI = 0xFf795577d9AC8bD7D90Ee22b6C1703490b6512FD;

    //LINK Token address
    address private constant LINK = 0xa36085F69e2889c224210F603D836748e7dC0088;

    constructor(address _addressProvider)
        public
        FlashLoanReceiverBase(_addressProvider)
    {
        uniswapRouter = IUniswapV2Router02(UNISWAP_ROUTER_ADDRESS);
    }

    function convertEthToDai(uint256 daiAmount) public payable {
        uint256 deadline = block.timestamp + 15;
        address[] memory path = getPathForETHtoDAI();
        IERC20 endToken = IERC20(path[0]);
        endToken.approve(address(uniswapRouter), daiAmount);
        uniswapRouter.swapETHForExactTokens{value: msg.value}(
            daiAmount,
            getPathForETHtoDAI(),
            address(this),
            deadline
        );
        // refund leftover ETH to user
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success, "refund failed");
    }

    function convertToken1ToToken2(address[] memory path, uint256 _amount)
        public
        payable
        returns (uint256[] memory)
    {
        uint256 deadline = block.timestamp + 15;
        IERC20 endToken = IERC20(path[0]);
        require(
            endToken.approve(address(uniswapRouter), _amount),
            "Error approving token"
        );
        uint256[] memory amounts = uniswapRouter.swapExactTokensForTokens(
            _amount,
            0.5 ether,
            path,
            address(this),
            deadline
        );
        // endToken.transfer(address(this), amounts[1]);
        return amounts;
        // refund leftover ETH to user
        // (bool success, ) = msg.sender.call{value: address(this).balance}("");
        // require(success, "refund failed");
    }

    function getEstimatedETHforDAI(uint256 daiAmount)
        public
        view
        returns (uint256[] memory)
    {
        return uniswapRouter.getAmountsIn(daiAmount, getPathForETHtoDAI());
    }

    function getPathForETHtoDAI() private view returns (address[] memory) {
        address[] memory path = new address[](2);
        // path[0] = uniswapRouter.WETH();
        path[0] = LINK;
        path[1] = DAI;
        return path;
    }

    function getPathForDAIToETH() private view returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = DAI;
        // path[1] = uniswapRouter.WETH();
        path[1] = LINK;
        return path;
    }

    /**
        This function is called after your contract has received the flash loaned amount
     */
    function executeOperation(
        address _reserve,
        uint256 _amount,
        uint256 _fee,
        bytes calldata _params
    ) external override {
        require(
            _amount <= getBalanceInternal(address(this), _reserve),
            "Invalid balance, was the flashLoan successful?"
        );

        //
        // Your logic goes here.
        // !! Ensure that *this contract* has enough of `_reserve` funds to payback the `_fee` !!
        //

        address[] memory pathFromEthToDai = getPathForETHtoDAI();
        uint256[] memory DaiAmounts = convertToken1ToToken2(
            pathFromEthToDai,
            _amount
        );

        //swapping back to ETHER from DAI
        address[] memory pathFromDaiToEth = getPathForDAIToETH();
        uint256[] memory EtherAmounts = convertToken1ToToken2(
            pathFromDaiToEth,
            DaiAmounts[1]
        );
        require(EtherAmounts[1] - _amount < 0, "Noo profits");
        uint256 totalDebt = _amount.add(_fee);

        transferFundsBackToPoolInternal(_reserve, totalDebt);
    }

    /**
        Flash loan 1000000000000000000 wei (1 ether) worth of `_asset`
        use the RESERVE ADDRESS FROM THE aave docs;
        for LINK Token  = 0xAD5ce863aE3E4E9394Ab43d4ba0D80f419F61789
     */
    function flashloan(address _asset, uint256 _amount) public onlyOwner {
        bytes memory data = "";
        // uint256 amount = 1 ether;

        ILendingPool lendingPool = ILendingPool(
            addressesProvider.getLendingPool()
        );
        lendingPool.flashLoan(address(this), _asset, _amount, data);
    }
}
