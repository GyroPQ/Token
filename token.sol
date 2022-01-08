// SPDX-License-Identifier: MIT

pragma solidity ^0.6.2;

import "github/OpenZeppelin/openzeppelin-contracts/contracts/GSN/Context.sol";
import "github/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "github/OpenZeppelin/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "github/OpenZeppelin/openzeppelin-contracts/contracts/utils/Address.sol";
import "github/OpenZeppelin/openzeppelin-contracts/contracts/access/Ownable.sol";
import "pancake/PancakeSwap.sol";

contract PoorQuackOT is Context, IERC20, Ownable {
    using SafeMath for uint256;
    using Address for address;

    mapping (address => uint256) public _rOwned;
    mapping (address => uint256) public _tOwned;
    mapping (address => uint256) private _buyMap;
    mapping (address => mapping (address => uint256)) private _allowances;

    mapping (address => bool) private _isExcluded;
    address[] private _excluded;

    uint256 private constant MAX = ~uint256(0);
    uint256 private _tTotal = 100000000000000000000000000000000;
    uint256 private _rTotal = (MAX - (MAX % _tTotal));
    uint256 private _tFeeTotal;

    string private _name = "PoorQUACK.com";
    string private _symbol = "POOR";
    uint8 private _decimals = 18;

    address payable public _wMegaPump = 0x19F1AFbCc0692B0e69E792F21827705Bba293D4f;
    address payable public _wBuyBack = 0x3E1b6a509800849306D9f440C22679b09f9e95a5;
    address payable public _wMarketing = 0x36E58a20C7b96B3503Dc9F2c6aba3af1f4876c83;

    uint256 public _currentTax = 14;   // 14% total tax
    uint256 public _totalTax = 14;   // 14% total tax
    uint256 private _previousRefTax = _totalTax;

    //time tax penalties
    uint256 public _tax24HR = 22;   // 22% total tax
    uint256 public _tax72HR = 18;   // 18% total tax
    
    //breakup of 14% tax
    uint256 public _refPer = 0; // 0% for reflection

    //use percentage function so value is different to refPer, these values are after reflection has been done. 
    //reflection is zero, but can be chnaged in the future.
    uint256 public _megaPumpPer = 1400; // 14% megapump
    uint256 public _autoLiqPer = 2100;  // 21% auto liqudity
    uint256 public _buyBacksPer = 1400;  // 14% buybacks/burn
    uint256 public _marketingPer = 5100;  // 51% marketing

    uint256 public _liqAllTime;
    uint256 public _megaPumpAllTime;
    uint256 public _buyBacksAllTime;
    uint256 public _marketingAllTime;
                                     
    uint256 public _maxHoldAmount =  1000000000000000000000000000000; 
    uint256 public _maxTransAmount = 1000000000000000000000000000000; 
    uint256 public _minTokensForLiquidity = 100000000000000000000000000000;                                  
    
    bool public _AutoTaxEnabled = false;
    bool public _lockLiquiditiesEnabled = false;
    bool _inLockLiquidities;

    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;

    modifier lockLiquidities{
        _inLockLiquidities = true;
        _;
        _inLockLiquidities = false;
    }

    constructor () public {

         IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

         // Create a uniswap pair for this new token
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        // set the rest of the contract variables
        uniswapV2Router = _uniswapV2Router;

        _rOwned[_msgSender()] = _rTotal;
        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    //to recieve BNB from uniswapV2Router when swapping
    receive() external payable {}

    function name() public view returns (string memory) {

        return _name;
    }

    function symbol() public view returns (string memory) {

        return _symbol;
    }

    function decimals() public view returns (uint8) {

        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {

        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {

        if (_isExcluded[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {

        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {

        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {

        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {

        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {

        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {

        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }

    function isExcluded(address account) public view returns (bool) {

        return _isExcluded[account];
    }

    function totalFees() public view returns (uint256) {

        return _tFeeTotal;
    }
    
    function removeTax() private {
        
        if(_totalTax == 0) return;
        
        _previousRefTax = _totalTax;
        
        _totalTax = 0;
    }
    
    function restoreTax() private {
        
        _totalTax = _previousRefTax;
    }

    function reflect(uint256 tAmount) public {

        address sender = _msgSender();
        require(!_isExcluded[sender], "Excluded addresses cannot call this function");
        (uint256 rAmount,,,,) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rTotal = _rTotal.sub(rAmount);
        _tFeeTotal = _tFeeTotal.add(tAmount);
    }

    function reflectionFromToken(uint256 tAmount, bool deductTransferFee) public view returns(uint256) {

        require(tAmount <= _tTotal, "Amount must be less than supply");
        if (!deductTransferFee) {
            (uint256 rAmount,,,,) = _getValues(tAmount);
            return rAmount;
        } else {
            (,uint256 rTransferAmount,,,) = _getValues(tAmount);
            return rTransferAmount;
        }
    }

    function tokenFromReflection(uint256 rAmount) public view returns(uint256) {

        require(rAmount <= _rTotal, "Amount must be less than total reflections");
        uint256 currentRate =  _getRate();
        return rAmount.div(currentRate);
    }

    function excludeAccount(address account) external onlyOwner() {

        require(!_isExcluded[account], "Account is already excluded");
        if(_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcluded[account] = true;
        _excluded.push(account);
    }

    function includeAccount(address account) external onlyOwner() {

        require(_isExcluded[account], "Account is already excluded");
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _tOwned[account] = 0;
                _isExcluded[account] = false;
                _excluded.pop();
                break;
            }
        }
    }

    function _approve(address owner, address spender, uint256 amount) private {

        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _isBuy(address _sender) private view returns (bool) {
        return _sender == uniswapV2Pair;
    }

    function _transfer(address sender, address recipient, uint256 amount) private {

        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        
        if(_AutoTaxEnabled && !_inLockLiquidities && sender != uniswapV2Pair) {
            _doTokenomics();
        }
        
        if(_isExcluded[sender] || _isExcluded[recipient]) {
            removeTax();

        } else {

            require(amount <= _maxTransAmount, "Transfer amount exceeds the maxTransAmount.");

            if (!_isBuy(sender)) {
                // 22% tax within 24 hours
                if (_buyMap[sender] != 0 && (_buyMap[sender] + (24 hours) >= block.timestamp))  {
                    _totalTax = _tax24HR;

                // 18% tax within 72 hours
                } else if(_buyMap[sender] != 0 && (_buyMap[sender] + (72 hours) >= block.timestamp)
                    && _buyMap[sender] != 0 && (_buyMap[sender] + (24 hours) < block.timestamp)) {
                    _totalTax = _tax72HR;
                
                } else {
                
                    _totalTax = _currentTax;
                }
            } else {

                uint256 recipient_balance = balanceOf(address(recipient));
                uint256 recipient_new_balance = recipient_balance.add(amount);
                require(recipient_new_balance < _maxHoldAmount, "Transfer amount exceeds the maxHoldAmount.");

                if (_buyMap[recipient] == 0) {
                    _buyMap[recipient] = block.timestamp;
                }
                _totalTax = _currentTax;
            }
        }
            
        if (_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferFromExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && _isExcluded[recipient]) {
            _transferToExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferStandard(sender, recipient, amount);
        } else if (_isExcluded[sender] && _isExcluded[recipient]) {
            _transferBothExcluded(sender, recipient, amount);
        } else {
            _transferStandard(sender, recipient, amount);
        }
        
        if(_isExcluded[sender] || _isExcluded[recipient]) {
            restoreTax();
        }
    }

    function _transferStandard(address sender, address recipient, uint256 tAmount) private {

        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferToExcluded(address sender, address recipient, uint256 tAmount) private {

        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferFromExcluded(address sender, address recipient, uint256 tAmount) private {

        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee) = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferBothExcluded(address sender, address recipient, uint256 tAmount) private {

        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee) = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _reflectFee(uint256 rFee, uint256 tFee) private {
        
        uint256 newTFee = tFee.div(100).mul(_refPer);
        uint256 newRFee = rFee.div(100).mul(_refPer);

        uint256 tContractFee = tFee.sub(newTFee);
        uint256 rContractFee = rFee.sub(newRFee);
        
        _tOwned[address(this)] = _tOwned[address(this)].add(tContractFee);
        _rOwned[address(this)] = _rOwned[address(this)].add(rContractFee);
        
        _rTotal = _rTotal.sub(newRFee);
        _tFeeTotal = _tFeeTotal.add(newTFee);
    }

    function _getValues(uint256 tAmount) private view returns (uint256, uint256, uint256, uint256, uint256) {

        (uint256 tTransferAmount, uint256 tFee) = _getTValues(tAmount);
        uint256 currentRate =  _getRate();
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(tAmount, tFee, currentRate);
        return (rAmount, rTransferAmount, rFee, tTransferAmount, tFee);
    }

    function _getTValues(uint256 tAmount) private view returns (uint256, uint256) {

        uint256 tFee = tAmount.mul(_totalTax).div(100); //14% tax is taken or whatever _totalTax is.
        uint256 tTransferAmount = tAmount.sub(tFee);
        return (tTransferAmount, tFee);
    }

    function _getRValues(uint256 tAmount, uint256 tFee, uint256 currentRate) private pure returns (uint256, uint256, uint256) {

        uint256 rAmount = tAmount.mul(currentRate);
        uint256 rFee = tFee.mul(currentRate);
        uint256 rTransferAmount = rAmount.sub(rFee);
        return (rAmount, rTransferAmount, rFee);
    }

    function _getRate() private view returns(uint256) {

        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply() private view returns(uint256, uint256) {

        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;

        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_rOwned[_excluded[i]] > rSupply || _tOwned[_excluded[i]] > tSupply) return (_rTotal, _tTotal);
            rSupply = rSupply.sub(_rOwned[_excluded[i]]);
            tSupply = tSupply.sub(_tOwned[_excluded[i]]);
        }

        if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }

    function setMaxTrans(uint256 maxTransAmount) external onlyOwner() {

        _maxTransAmount = maxTransAmount;
    }

    function _setTotalTax(uint256 totalTax) external onlyOwner() {

        _currentTax = totalTax;
        _totalTax = totalTax;
    }
    
    function _set24Tax(uint256 totalTax) external onlyOwner() {

        _tax24HR = totalTax;
    }

    function _set72Tax(uint256 totalTax) external onlyOwner() {

        _tax72HR = totalTax;
    }

    function _setRefPer(uint256 refPer) external onlyOwner() {

        _refPer = refPer;
    }

    function _setMegaPumpPer(uint256 megaPumpPer) external onlyOwner() {

        _megaPumpPer = megaPumpPer;
    }

    function _setAutoLiqPer(uint256 autoLiqPer) external onlyOwner() {

        _autoLiqPer = autoLiqPer;
    }

    function _setBuyBacksPer(uint256 buyBacksPer) external onlyOwner() {

        _buyBacksPer = buyBacksPer;
    }

    function _setMarketingPer(uint256 marketingPer) external onlyOwner() {

        _marketingPer = marketingPer;
    }

    function _setMinTokensForLiquidity(uint256 minTokensForLiquidity) external onlyOwner() {

        _minTokensForLiquidity = minTokensForLiquidity;
    }

    function _setLockLiquiditiesEnabled(bool lockLiquiditiesEnabled) external onlyOwner() {

        _lockLiquiditiesEnabled = lockLiquiditiesEnabled;
    }
    
    function _setAutoTaxEnabled(bool AutoTaxEnabled) external onlyOwner() {

        _AutoTaxEnabled = AutoTaxEnabled;
    }

    function _doTokenomics() public lockLiquidities {
        
        uint256 amount = balanceOf(address(this));
        
        if(amount >= _minTokensForLiquidity && _lockLiquiditiesEnabled == true && amount > 0) {

            if(amount >= _maxTransAmount) {
                amount = _maxTransAmount;
            }

            uint256 liqAmount = _findPercent(amount, _autoLiqPer);
            uint256 megaPumpAmount = _findPercent(amount, _megaPumpPer);
            uint256 buybacksAmount = _findPercent(amount, _buyBacksPer);
            uint256 marketingAmount = amount.sub(liqAmount).sub(megaPumpAmount).sub(buybacksAmount);
    
            _doLiquidity(liqAmount);
            _doMegaPump(megaPumpAmount);
            _doBuyBack(buybacksAmount);
            _doMarketing(marketingAmount);
        }
    }

    function _doLiquidity(uint256 amount) private {

        _liqAllTime += amount;

        uint256 bnbHalf = amount.div(2);
        uint256 tokenHalf = amount.sub(bnbHalf);

        uint256 bnbBalance = address(this).balance; //current bnb balance

        swapTokensForEth(bnbHalf, address(this)); //swap half to bnb

        uint256 bnbNewBalance = address(this).balance.sub(bnbBalance); //get amount swapped to bnb

        addLiquidity(tokenHalf, bnbNewBalance); //add liquidity using the tokens and bnb
    }

    function _doMegaPump(uint256 amount) private {

        uint256 bnbBalance = address(this).balance; //current bnb balance

        swapTokensForEth(amount, address(this)); //swap T1 liquidity for BNB

        uint256 bnbNewBalance = address(this).balance.sub(bnbBalance); //get amount swapped to bnb

        _wMegaPump.transfer(bnbNewBalance); //send bnb amount to governance

        _megaPumpAllTime += bnbNewBalance;
    }

    function _doBuyBack(uint256 amount) private {

        uint256 bnbBalance = address(this).balance; //current bnb balance

        swapTokensForEth(amount, address(this)); //swap buyback tokens liquidity for BNB

        uint256 bnbNewBalance = address(this).balance.sub(bnbBalance); //get amount swapped to bnb

        _wBuyBack.transfer(bnbNewBalance); //send bnb amount to governance

        _buyBacksAllTime += bnbNewBalance;
    }

    function _doMarketing(uint256 amount) private {

        uint256 bnbBalance = address(this).balance; //current bnb balance

        swapTokensForEth(amount, address(this)); //swap buyback tokens liquidity for BNB

        uint256 bnbNewBalance = address(this).balance.sub(bnbBalance); //get amount swapped to bnb

        _wMarketing.transfer(bnbNewBalance); //send bnb amount to governance

        _marketingAllTime += bnbNewBalance;
    }

    function _findPercent(uint256 value, uint256 basePercent) private pure returns (uint256)  {

        uint256 percent = value.mul(basePercent).div(10000);
        return percent;
    }
    
    function swapTokensForEth(uint256 tokenAmount, address tokenContract) private {

        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = tokenContract;
        path[1] = uniswapV2Router.WETH();

        _approve(tokenContract, address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            tokenContract,
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {

        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            owner(),
            block.timestamp
        );
    }

    function marketingFallBack() public onlyOwner() {

         if(balanceOf(address(this)) > 0) {
            this.transfer(_wMarketing, balanceOf(address(this)));
         }

         if(address(this).balance > 0) {
            _wMarketing.transfer(address(this).balance);
         }
    }

    function setRouterAddress(address newRouter) public onlyOwner() {

        IUniswapV2Router02 _newPancakeRouter = IUniswapV2Router02(newRouter);
        uniswapV2Pair = IUniswapV2Factory(_newPancakeRouter.factory()).createPair(address(this), _newPancakeRouter.WETH());
        uniswapV2Router = _newPancakeRouter;
    }
    
    function setMegaPumpWallet(address payable wallet) public onlyOwner() {

        _wMegaPump = wallet;
    }
    
    function setBuyBackWallet(address payable wallet) public onlyOwner() {

        _wBuyBack = wallet;
    }

    function setMarketingWallet(address payable wallet) public onlyOwner() {

        _wMarketing = wallet;
    }
}