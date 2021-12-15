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
    address private constant DAI = 0x4F96Fe3b7A6Cf9725f59d353F723c1bDb64CA6Aa;

    constructor(address _addressProvider)
        public
        FlashLoanReceiverBase(_addressProvider)
    {
        uniswapRouter = IUniswapV2Router02(UNISWAP_ROUTER_ADDRESS);
    }

    function convertEthToDai(uint256 daiAmount) public payable {
        uint256 deadline = block.timestamp + 15;
        address[] memory path = getPathForETHtoDAI();
        IERC20 endToken = IERC20(path[1]);
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
        IERC20 endToken = IERC20(path[1]);
        endToken.approve(address(uniswapRouter), _amount);
        uint256[] memory amounts = uniswapRouter.swapExactTokensForTokens(
            _amount,
            1 ether,
            path,
            address(this),
            deadline
        );

        endToken.transfer(address(this), amounts[1]);
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
        path[0] = uniswapRouter.WETH();
        path[1] = DAI;
        return path;
    }

    function getPathForDAIToETH() private view returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = DAI;
        path[1] = uniswapRouter.WETH();
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

        //profit _amount - EtherAmounts[1]

        uint256 totalDebt = _amount.add(_fee);

        // for (uint256 i = 0; i < assets.length; i++) {
        //     uint256 amountOwing = amounts[i].add(premiums[i]);
        //     IERC20(assets[i]).approve(address(LENDING_POOL), amountOwing);
        // }

        // return true;

        transferFundsBackToPoolInternal(_reserve, totalDebt);
    }

    /**
        Flash loan 1000000000000000000 wei (1 ether) worth of `_asset`
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
