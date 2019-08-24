pragma solidity >= 0.4.25;

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

contract FlightSuretyData {
    using SafeMath for uint256;

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    address private contractOwner;                                      // Account used to deploy contract
    bool private operational = true;                                    // Blocks all state changes throughout the contract if false

    struct Airline{
        string name;
        bool isRegistered;
        bool isFunded;
        uint256 fund;
    }
    struct PassengerPurchase{
        uint256 balance;
        uint256 insuranceCredit;
    }
    mapping(address => Airline) airline;
    mapping(address => mapping(bytes32 => PassengerPurchase)) passengers;
   mapping(address => uint256) private authorizedContracts;
    uint256 airlinesCount;
    uint256 fundedAirlinesCount;
    /********************************************************************************************/
    /*                                       EVENT DEFINITIONS                                  */
    /********************************************************************************************/


    /**
    * @dev Constructor
    *      The deploying account becomes contractOwner
    */
    constructor
                                (
                                    address firstAirline,
                                    string memory airlineName
                                ) 
                                public 
    {
        contractOwner = msg.sender;

        airline[firstAirline].name = airlineName;
        airline[firstAirline].isRegistered = true;
        airline[firstAirline].isFunded = true;
        airline[firstAirline].fund = 0;

        airlinesCount = 1;
        fundedAirlinesCount = 0; //why not 1!??
    }

    /********************************************************************************************/
    /*                                       FUNCTION MODIFIERS                                 */
    /********************************************************************************************/

    // Modifiers help avoid duplication of code. They are typically used to validate something
    // before a function is allowed to be executed.

    /**
    * @dev Modifier that requires the "operational" boolean variable to be "true"
    *      This is used on all state changing functions to pause the contract in 
    *      the event there is an issue that needs to be fixed
    */
    modifier requireIsOperational() 
    {
        require(operational, "Contract is currently not operational");
        _;  // All modifiers require an "_" which indicates where the function body will be added
    }

    /**
    * @dev Modifier that requires the "ContractOwner" account to be the function caller
    */
    modifier requireContractOwner()
    {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    modifier isAuthorizedCaller(){
        require(authorizedContracts[msg.sender] == 1, "Caller is not authorized!");
        _;
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    function getAirlinesCount () external view returns(uint256){
        return airlinesCount;
    }

    function getFundedAirlinesCount () external view returns(uint256){
        return fundedAirlinesCount;
    }

    function getAirline (address airlineAdd) external view isAuthorizedCaller returns(string memory name, bool isRegistered, bool isFunded) {
        name = airline[airlineAdd].name;
        isRegistered =airline[airlineAdd].isRegistered;
        isFunded = airline[airlineAdd].isFunded;
    }

/**
    * @dev Check if an Airline is registered
    *
    * @return A bool that indicates if the Airline is registered
    */   
    function isAirlineRegistered
                            (
                                address _address
                            )
                            external
                            view
                            returns(bool)
    {
        return airline[_address].isRegistered;
    }

    function isAirlineFunded
                            (
                                address _address
                            )
                            external
                            view
                            returns(bool)
    {
        return airline[_address].isFunded;
    }

   

    function authorizeContract
                            (
                                address contractAddress
                            )
                            external
                            requireContractOwner
    {
        authorizedContracts[contractAddress] = 1;
    }

    function deauthorizeContract
                            (
                                address contractAddress
                            )
                            external
                            requireContractOwner
    {
        delete authorizedContracts[contractAddress];
    }

 /**
    * @dev Get operating status of contract
    *
    * @return A bool that is the current operating status
    */      
    function isOperational() 
                            public 
                            view 
                            returns(bool) 
    {
        return operational;
    }

    /**
    * @dev Sets contract operations on/off
    *
    * When operational mode is disabled, all write transactions except for this one will fail
    */    
    function setOperatingStatus
                            (
                                bool mode
                            ) 
                            external
                            requireContractOwner 
    {
        operational = mode;
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

   /**
    * @dev Add an airline to the registration queue
    *      Can only be called from FlightSuretyApp contract
    *
    */  

    function registerAirline
                            (   address airlineAdd,
                                string airlineName
                            )
                            external
    {
        airline[airlineAdd].name = airlineName;
        airline[airlineAdd].isRegistered = true;
        airlinesCount = airlinesCount.add(1);
    }


   /**
    * @dev Buy insurance for a flight
    *
    */   
    function buy
                            ( 
                                address passengerAdd,
                                bytes32 flight                            
                            )
                            external
                            payable
    {
        passengers[passengerAdd][flight] = PassengerPurchase(msg.value, 0 ether);
    }

    
    function getPassengerPurchase(address passengerAdd, bytes32 flight) external view returns(uint256 balance, uint256 insuranceCredit  ){
        balance = passengers[passengerAdd][flight].balance;
        insuranceCredit = passengers[passengerAdd][flight].insuranceCredit;
    }

    /**
     *  @dev Credits payouts to insurees
    */

    function creditInsurees
                                (
                                    address passengerAdd, uint256 amount ,bytes32 flight
                                )
                                external
                                
    {
        passengers[passengerAdd][flight].insuranceCredit = amount;

    }
    

    /**
     *  @dev Transfers eligible payout funds to insuree
     *
    */
    function withdraw
                            (
                                address passengerAdd,
                                bytes32 flight
                            )
                            external
                            
    {
        uint256 amount = passengers[passengerAdd][flight].insuranceCredit;
        require(amount > 0, "No insurance credit!");
        passengers[passengerAdd][flight].insuranceCredit =0;
        passengerAdd.transfer(amount);
    }
/**
    * @dev Initial funding for the insurance. Unless there are too many delayed flights
    *      resulting in insurance payouts, the contract should be self-sustaining
    *
    */ 
    function fund
                            (
                            )
                            public
                            payable                            
    {
    }

    function fundAirline (address airlineAdd) external payable {
        airline[airlineAdd].fund = msg.value.add(airline[airlineAdd].fund);

        if (airline[airlineAdd].fund >= 10){
            airline[airlineAdd].isFunded = true;
            fundedAirlinesCount = fundedAirlinesCount.add(1);
        }
    }

    function getFlightKey
                        (
                            address airlineAdd,
                            string memory flight,
                            uint256 timestamp
                        )
                        pure
                        internal
                        returns(bytes32) 
    {
        return keccak256(abi.encodePacked(airlineAdd, flight, timestamp));
    }

    /**
    * @dev Fallback function for funding smart contract.
    *
    */
    function() 
                            external 
                            payable 
    {
        fund();
    }


}

