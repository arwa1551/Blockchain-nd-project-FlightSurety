
var Test = require('../config/testConfig.js');
var BigNumber = require('bignumber.js');

contract('Flight Surety Tests', async (accounts) => {

  var config;
  let passenger = accounts[7];
  let oracles = accounts.slice(9, 40);
  const MAX_INSURANCE_AMOUNT = web3.utils.toWei('1', 'ether');
  const STATUS_CODE_AIRLINE_DELAY = 20;
  const STATUS_CODE_ON_TIME = 10;
  let flight = 'BND190';
  let timestamp = Math.floor(new Date().getTime() / 1000);

  before('setup contract', async () => {
    config = await Test.Config(accounts);
    await config.flightSuretyData.authorizeContract(config.flightSuretyApp.address);
    
  });

  /****************************************************************************************/
  /* Operations and Settings                                                              */
  /****************************************************************************************/

  it(`(multiparty) has correct initial isOperational() value`, async function () {

    // Get operating status
    let status = await config.flightSuretyData.isOperational.call();
    assert.equal(status, true, "Incorrect initial operating status value");

  });

  it(`(multiparty) can block access to setOperatingStatus() for non-Contract Owner account`, async function () {

      // Ensure that access is denied for non-Contract Owner account
      let accessDenied = false;
      try 
      {
          await config.flightSuretyData.setOperatingStatus(false, { from: config.testAddresses[2] });
      } 
      catch(e){
          accessDenied = true;
      }
      assert.equal(accessDenied, true, "Access not restricted to Contract Owner");
            
  });

  it(`(multiparty) can allow access to setOperatingStatus() for Contract Owner account`, async function () {

      // Ensure that access is allowed for Contract Owner account
      let accessDenied = false;
      try 
      {
          await config.flightSuretyData.setOperatingStatus(false);
      }
      catch(e) {
          accessDenied = true;
      }
      assert.equal(accessDenied, false, "Access not restricted to Contract Owner");
      
  });

  it(`(multiparty) can block access to functions using requireIsOperational when operating status is false`, async function () {

      await config.flightSuretyData.setOperatingStatus(false);

      let reverted = false;
      try 
      {
          await config.flightSurety.setTestingMode(true);
      }
      catch(e) {
          reverted = true;
      }
      assert.equal(reverted, true, "Access not blocked for requireIsOperational");      

      // Set it back for other tests to work
      await config.flightSuretyData.setOperatingStatus(true);

  });

  it('(airline) cannot register an Airline using registerAirline() if it is not funded', async () => {
    
    // ARRANGE
    let newAirline = accounts[2];

    // ACT
    try {
        await config.flightSuretyApp.registerAirline(newAirline, {from: config.firstAirline});
    }
    catch(e) {

    }
    let result = await config.flightSuretyData.isAirlineRegistered.call(newAirline); 

    // ASSERT
    assert.equal(result, false, "Airline should not be able to register another airline if it hasn't provided funding");

  });

  it(`(airline) First ailrline is registered`, async () =>{
    let result = await config.flightSuretyData.isAirlineRegistered(config.firstAirline);
    
    assert.equal(result, true, 'first airline should be registered');
});

  it (`(airline) only existing funded airline may register a new airline `, async () =>{

    let result = false;
    let newAirline = accounts[2];

    try{
        await config.flightSuretyApp.fundAirline({from: config.firstAirline, value: config.weiMultiple});
        await config.flightSuretyApp.registerAirline(newAirline, 'New Airline', {from: config.firstAirline});
        result = await config.flightSuretyData.isAirlineRegistered(newAirline);

    }catch (e){
        console.log(e)
    }

    assert.equal(result, true, 'Airline should register another one if it is funded');
  });

  
  it(`(multiparty) should not register 5th airline with less than 50% votes`, async() => {
      let result= true;
      let votingAirlines = accounts.slice(3,5);
      let testAirline = accounts[5];
      let testAirlineName = 'Test Airline';

      try{
      for (let i=0; i < votingAirlines.length; i++){
          await config.flightSuretyApp.registerAirline(votingAirlines[i], `Voting Airline ${i}`, {from: config.firstAirline});
      }
      await config.flightSuretyApp.registerAirline(testAirline, testAirlineName, {from: config.firstAirline});
      result = await config.flightSuretyData.isAirlineRegistered(testAirline);
    }catch(e){
        console.log(e);
    }

    assert.equal(result, false, "Airline should not be registered if less than 50% votes");

  });

  it(`(multiparty) should register 5th airline with more than 50% votes`, async() => {
    let result = false;
    let testAirline = accounts[5];

    try{

        await config.flightSuretyApp.voteForAirline(testAirline, {from: config.firstAirline});

        result = await config.flightSuretyData.isAirlineRegistered(testAirline);

    }catch(e){
        console.log(e);
    }
    assert.equal(result, true, "Airline should be registered if more than 50% votes");
  });

  it(`(flights) Funded airlines can register flights`, async() =>{
      let result = true; 

      try{
          await config.flightSuretyApp.registerFlight(flight, timestamp, {from: config.firstAirline});

      }catch (e){
          console.log(e);
          result = false;
      }
      assert.equal(result, true, "Airline should be to register flight");
  });
  
  it(`(passenger) Passengers may pay up to 1 ether for purchasing flight insurance`, async() =>{
      let result = true ;

      try{
          await config.flightSuretyApp.buyInsurance(config.firstAirline, flight,timestamp, {from: passenger, value: MAX_INSURANCE_AMOUNT});

      }catch(e){
          result = false;
          console.log(e);
      }
      assert.equal(result, true, "Passengers should be able to buy insurance");
  });

  
  it('can register oracles', async () => {
    
    // ARRANGE
    let fee = await config.flightSuretyApp.REGISTRATION_FEE.call();

    // ACT
    for(let a=0; a<oracles.length; a++) {      
      await config.flightSuretyApp.registerOracle({ from: oracles[a], value: fee });
      let result = await config.flightSuretyApp.getMyIndexes.call({from: oracles[a]});
      console.log(`Oracle Registered: ${result[0]}, ${result[1]}, ${result[2]}`);
    }
  });

  it('can request flight status', async () => {
    // Submit a request for oracles to get status information for a flight
    await config.flightSuretyApp.fetchFlightStatus(config.firstAirline, flight, timestamp);
    // ACT

    // Since the Index assigned to each test account is opaque by design
    // loop through all the accounts and for each account, all its Indexes (indices?)
    // and submit a response. The contract will reject a submission if it was
    // not requested so while sub-optimal, it's a good test of that feature
    for(let a=0; a<oracles.length; a++) {

      // Get oracle information
      let oracleIndexes = await config.flightSuretyApp.getMyIndexes.call({ from: oracles[a]});
      for(let idx=0;idx< oracleIndexes.length;idx++) {

        try {
          // Submit a response...it will only be accepted if there is an Index match
         await config.flightSuretyApp.submitOracleResponse(oracleIndexes[idx], config.firstAirline, flight, timestamp, STATUS_CODE_ON_TIME, { from: oracles[a] });
        }
        catch(e) {
          // Enable this when debugging
           console.log('\nError', idx, oracleIndexes[idx].toNumber(), flight, timestamp);
        }

      }
    }

  });

  

});
