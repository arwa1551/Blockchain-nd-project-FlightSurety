pragma solidity >= 0.4.25;

// It's important to avoid vulnerabilities due to numeric overflow bugs
// OpenZeppelin's SafeMath library, when used correctly, protects agains such bugs
// More info: https://www.nccgroup.trust/us/about-us/newsroom-and-events/blog/2018/november/smart-contract-insecurity-bad-arithmetic/

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

/************************************************** */
/* FlightSurety Smart Contract                      */
/************************************************** */
contract FlightSuretyApp {
    using SafeMath for uint256; // Allow SafeMath functions to be called for all uint256 types (similar to "prototype" in Javascript)

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/
    FlightSuretyData flightSuretyData;

    uint256 public constant MAX_INSURANCE_COST = 1 ether;
    uint256 private constant AIRLINE_VOTING_THRESHOLD = 4;
    uint256 public constant MINIMUM_FUND = 10 ether;

    // Flight status codees
    uint8 private constant STATUS_CODE_UNKNOWN = 0;
    uint8 private constant STATUS_CODE_ON_TIME = 10;
    uint8 private constant STATUS_CODE_LATE_AIRLINE = 20;
    uint8 private constant STATUS_CODE_LATE_WEATHER = 30;
    uint8 private constant STATUS_CODE_LATE_TECHNICAL = 40;
    uint8 private constant STATUS_CODE_LATE_OTHER = 50;

    address private contractOwner;          // Account used to deploy contract

    struct Flight {
        bool isRegistered;
        uint8 statusCode;
        uint256 updatedTimestamp;        
        address airline;
    }
    struct Airline {
        string name;
        bool pending;
    }
     mapping (address => Airline) pendingAirlines;
    mapping(bytes32 => Flight) private flights;
    mapping(bytes32 => address[]) private passengers;
    mapping (address => address[]) votes;

 
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
         // Modify to call data contract's status
        require(true, "Contract is currently not operational");  
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

    modifier requireFundedAirline(address airlineAdd){
        bool isFunded;
        (,,isFunded) = flightSuretyData.getAirline(airlineAdd);
        require(isFunded == true , "Airline is not funded");
        _;
    }

    modifier requireRegisteredAirline(address airlineAdd){
        require(flightSuretyData.isAirlineRegistered(airlineAdd) == true, "Airline is not registered");
        _;
    }

    modifier requireNotRegisteredAirline(address airlineAdd){
        require(flightSuretyData.isAirlineRegistered(airlineAdd) == false, "Airline is already registered");
        _;
    }

    modifier requirePendingAirline(address airlineAdd) 
    {
        require(pendingAirlines[airlineAdd].pending == true, "Airline is not pending registeration");
        _;
    }

    modifier requireNotPendingAirline(address airlineAdd) 
    {
        require(pendingAirlines[airlineAdd].pending == false, "Airline is pending registeration");
        _;
    }

    /********************************************************************************************/
    /*                                       CONSTRUCTOR                                        */
    /********************************************************************************************/

    /**
    * @dev Contract constructor
    *
    */
    constructor
                                (
                                    address dataContract
                                ) 
                                public 
    {
        contractOwner = msg.sender;
        flightSuretyData = FlightSuretyData(dataContract);
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    function isOperational() 
                            public 
                            pure 
                            returns(bool) 
    {
        return true;  // Modify to call data contract's status
    }

    function isPending(address airlineAdd) external view returns(bool){
        return pendingAirlines[airlineAdd].pending;
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/
    function voteForAirline(address airlineAdd) external 
                            requireFundedAirline(msg.sender) 
                            requirePendingAirline(airlineAdd)
                            requireNotRegisteredAirline(airlineAdd)
                            {
        require(flightSuretyData.getAirlinesCount() >= AIRLINE_VOTING_THRESHOLD, "less than voting threshold");

        bool isDuplicate = false;
        //make sure that msg.sender has not voted before
        for (uint i =0; i<votes[airlineAdd].length; i++){
            if (votes[airlineAdd][i] == msg.sender){
                isDuplicate = true;
                break;
            }
        }

        require(isDuplicate == false, "Airline already voted!");

        votes[airlineAdd].push(msg.sender);

        if (votes[airlineAdd].length > flightSuretyData.getFundedAirlinesCount().div(2)){
            flightSuretyData.registerAirline(airlineAdd, pendingAirlines[airlineAdd].name);
            delete pendingAirlines[airlineAdd];
            delete votes[airlineAdd];

        }
                                

    }
  
   /**
    * @dev Add an airline to the registration queue
    *
    */   
    function registerAirline
                            ( 
                                address airlineAdd,
                                string airlineName  
                            )
                            external
                            requireNotRegisteredAirline(airlineAdd)
                            requireFundedAirline(msg.sender)
                            requireNotPendingAirline(airlineAdd)
    {
        if(flightSuretyData.getAirlinesCount() < AIRLINE_VOTING_THRESHOLD){ //for the first 4 airlines
            flightSuretyData.registerAirline(airlineAdd, airlineName);
        }else{
            pendingAirlines[airlineAdd] = Airline(airlineName, true);
        }
    }

    function fundAirline() external payable requireRegisteredAirline(msg.sender){
        flightSuretyData.fundAirline.value(msg.value)(msg.sender);
    }

    function buyInsurance(address airlineAdd, string flight, uint256 timestamp) external payable{
        require(msg.value <= MAX_INSURANCE_COST, "Exceeded max allowed insurance amount");
        bytes32 key = getFlightKey(airlineAdd, flight, timestamp);

        require(flights[key].isRegistered, "Flight is not registered");
        passengers[key].push(msg.sender);
        flightSuretyData.buy.value(msg.value)(msg.sender, key);
    }


   /**
    * @dev Register a future flight for insuring.
    *
    */  
    function registerFlight
                                (
                                    string flight,
                                    uint256 timestamp
                                )
                                external
    {
        bytes32 flightKey = getFlightKey(msg.sender, flight, timestamp);
        require(!flights[flightKey].isRegistered, "Flight is already regestered");
        flights[flightKey] = Flight(true, STATUS_CODE_UNKNOWN, timestamp, msg.sender);
        passengers[flightKey] = new address[](0);
    }
    
   /**
    * @dev Called after oracle has updated flight status
    *
    */  
    function processFlightStatus
                                (
                                    address airline,
                                    string memory flight,
                                    uint256 timestamp,
                                    uint8 statusCode
                                )
                                internal
    {
        bytes32 flightKey = getFlightKey(airline, flight, timestamp);
        require(flights[flightKey].isRegistered, "Flight is not registered!");
        flights[flightKey].statusCode = statusCode;

        if(flights[flightKey].statusCode == STATUS_CODE_LATE_AIRLINE){
            for(uint8 i=0; i < passengers[flightKey].length; i++){
                 creditInsurance(passengers[flightKey][i], airline, flight, timestamp);
            }
        }
    }

    function creditInsurance(address passengerAdd, address airline, string memory flight, uint256 timestamp) internal{
        bytes32 key = getFlightKey(airline, flight,timestamp);
        uint256 balance;
        (balance, ) = flightSuretyData.getPassengerPurchase(passengerAdd, key);
        flightSuretyData.creditInsuree(passengerAdd, balance.div(uint(2)), key);
    }

    function withdraw(address airlineAdd, string flight, uint256 timestamp) external{
        bytes32 flightKey = getFlightKey(airlineAdd, flight,timestamp);
        flightSuretyData.withdraw(msg.sender, flightKey);
    }


    // Generate a request for oracles to fetch flight information
    function fetchFlightStatus
                        (
                            address airline,
                            string flight,
                            uint256 timestamp                            
                        )
                        external
    {
        uint8 index = getRandomIndex(msg.sender);

        // Generate a unique key for storing the request
        bytes32 key = keccak256(abi.encodePacked(index, airline, flight, timestamp));
        oracleResponses[key] = ResponseInfo({
                                                requester: msg.sender,
                                                isOpen: true
                                            });

        emit OracleRequest(index, airline, flight, timestamp);
    } 


// region ORACLE MANAGEMENT

    // Incremented to add pseudo-randomness at various points
    uint8 private nonce = 0;    

    // Fee to be paid when registering oracle
    uint256 public constant REGISTRATION_FEE = 1 ether;

    // Number of oracles that must respond for valid status
    uint256 private constant MIN_RESPONSES = 3;


    struct Oracle {
        bool isRegistered;
        uint8[3] indexes;        
    }

    // Track all registered oracles
    mapping(address => Oracle) private oracles;

    // Model for responses from oracles
    struct ResponseInfo {
        address requester;                              // Account that requested status
        bool isOpen;                                    // If open, oracle responses are accepted
        mapping(uint8 => address[]) responses;          // Mapping key is the status code reported
                                                        // This lets us group responses and identify
                                                        // the response that majority of the oracles
    }

    // Track all oracle responses
    // Key = hash(index, flight, timestamp)
    mapping(bytes32 => ResponseInfo) private oracleResponses;

    // Event fired each time an oracle submits a response
    event FlightStatusInfo(address airline, string flight, uint256 timestamp, uint8 status);

    event OracleReport(address airline, string flight, uint256 timestamp, uint8 status);

    // Event fired when flight status request is submitted
    // Oracles track this and if they have a matching index
    // they fetch data and submit a response
    event OracleRequest(uint8 index, address airline, string flight, uint256 timestamp);


    // Register an oracle with the contract
    function registerOracle
                            (
                            )
                            external
                            payable
    {
        // Require registration fee
        require(msg.value >= REGISTRATION_FEE, "Registration fee is required");

        uint8[3] memory indexes = generateIndexes(msg.sender);

        oracles[msg.sender] = Oracle({
                                        isRegistered: true,
                                        indexes: indexes
                                    });
    }

    function getMyIndexes
                            (
                            )
                            view
                            external
                            returns(uint8[3] memory)
    {
        require(oracles[msg.sender].isRegistered, "Not registered as an oracle");

        return oracles[msg.sender].indexes;
    }




    // Called by oracle when a response is available to an outstanding request
    // For the response to be accepted, there must be a pending request that is open
    // and matches one of the three Indexes randomly assigned to the oracle at the
    // time of registration (i.e. uninvited oracles are not welcome)
    function submitOracleResponse
                        (
                            uint8 index,
                            address airline,
                            string flight,
                            uint256 timestamp,
                            uint8 statusCode
                        )
                        external
    {
        require((oracles[msg.sender].indexes[0] == index) || (oracles[msg.sender].indexes[1] == index) || (oracles[msg.sender].indexes[2] == index), "Index does not match oracle request");


        bytes32 key = keccak256(abi.encodePacked(index, airline, flight, timestamp)); 
        require(oracleResponses[key].isOpen, "Flight or timestamp do not match oracle request");

        oracleResponses[key].responses[statusCode].push(msg.sender);

        // Information isn't considered verified until at least MIN_RESPONSES
        // oracles respond with the *** same *** information
        emit OracleReport(airline, flight, timestamp, statusCode);
        if (oracleResponses[key].responses[statusCode].length >= MIN_RESPONSES) {
                oracleResponses[key].isOpen = false;
            emit FlightStatusInfo(airline, flight, timestamp, statusCode);

            // Handle flight status as appropriate
            processFlightStatus(airline, flight, timestamp, statusCode);
        }
    }


    function getFlightKey
                        (
                            address airline,
                            string memory flight,
                            uint256 timestamp
                        )
                        pure
                        internal
                        returns(bytes32) 
    {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    // Returns array of three non-duplicating integers from 0-9
    function generateIndexes
                            (                       
                                address account         
                            )
                            internal
                            returns(uint8[3] memory)
    {
        uint8[3] memory indexes;
        indexes[0] = getRandomIndex(account);
        
        indexes[1] = indexes[0];
        while(indexes[1] == indexes[0]) {
            indexes[1] = getRandomIndex(account);
        }

        indexes[2] = indexes[1];
        while((indexes[2] == indexes[0]) || (indexes[2] == indexes[1])) {
            indexes[2] = getRandomIndex(account);
        }

        return indexes;
    }

    // Returns array of three non-duplicating integers from 0-9
    function getRandomIndex
                            (
                                address account
                            )
                            internal
                            returns (uint8)
    {
        uint8 maxValue = 10;

        // Pseudo random number...the incrementing nonce adds variation
        uint8 random = uint8(uint256(keccak256(abi.encodePacked(blockhash(block.number - nonce++), account))) % maxValue);

        if (nonce > 250) {
            nonce = 0;  // Can only fetch blockhashes for last 256 blocks so we adapt
        }

        return random;
    }

// endregion

}   

contract FlightSuretyData{
    function getPassengerPurchase(address passengerAdd, bytes32 flight) external view returns(uint256 balance, uint256 insuranceCredit  );
    function creditInsuree(address passengerAdd, uint256 amount ,bytes32 flight) external;
    function getAirline (address airlineAdd) external view returns(string memory name, bool isRegistered, bool isFunded);
    function isAirlineRegistered(address _address) external returns(bool);
    function getAirlinesCount () external view returns(uint256);
    function getFundedAirlinesCount () external view returns(uint256);  
    function registerAirline(address airlineAdd, string airlineName)external;
    function fundAirline (address airlineAdd) external payable;
    function buy(address passengerAdd,bytes32 flight) external payable;
    function withdraw(address passengerAdd, bytes32 flight) external;
                            
}