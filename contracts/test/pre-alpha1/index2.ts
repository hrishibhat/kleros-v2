//challenged- dishonest challenger

import { expect } from "chai";
import { deployments, ethers, getNamedAccounts, network } from "hardhat";
import { BigNumber } from "ethers";
import {
  IncrementalNG,
  PNK,
  KlerosCore,
  FastBridgeReceiverOnEthereum,
  ForeignGatewayOnEthereum,
  ArbitrableExample,
  FastBridgeSenderToEthereum,
  HomeGatewayToEthereum,
  ArbSys,
  Inbox
} from "../../typechain-types";
import { OutgoingMessage } from "http";

/* eslint-disable no-unused-vars */

describe("Demo pre-alpha1", function () {
  const ONE_TENTH_ETH = BigNumber.from(10).pow(17);
  const ONE_ETH = BigNumber.from(10).pow(18);
  const ONE_HUNDRED_PNK = BigNumber.from(10).pow(20);
  const ONE_THOUSAND_PNK = BigNumber.from(10).pow(21);

  const enum Period {
    evidence,
    commit,
    vote,
    appeal,
    execution,
  }

  let deployer, relayer, bridger, challenger, innocentBystander;
  let ng, disputeKit, pnk, core, fastBridgeReceiver, foreignGateway, arbitrable, fastBridgeSender, homeGateway, safeBridgeArb, safeBridgeEth, arbsys, inbox;

  before("Setup", async () => {
    deployer = (await getNamedAccounts()).deployer;
    relayer = (await getNamedAccounts()).relayer;
  
    console.log("deployer:%s", deployer);
    console.log("named accounts: %O", await getNamedAccounts());


    // await deployments.fixture(["Arbitration", "ForeignGateway", "HomeGateway"], { // @note : this caused a the 3 contracts to have fresh deployment
    //   fallbackToGlobal: true,
    //   keepExistingDeployments: true,
    // });
    ng = <IncrementalNG>await ethers.getContract("IncrementalNG");
    disputeKit = <KlerosCore>await ethers.getContract("DisputeKitClassic");
    pnk = <PNK>await ethers.getContract("PNK");
    core = <KlerosCore>await ethers.getContract("KlerosCore");
    fastBridgeReceiver = <FastBridgeReceiverOnEthereum>await ethers.getContract("FastBridgeReceiverOnEthereum");
    foreignGateway = <ForeignGatewayOnEthereum>await ethers.getContract("ForeignGatewayOnEthereum");
    arbitrable = <ArbitrableExample>await ethers.getContract("ArbitrableExample");
    fastBridgeSender = <FastBridgeSenderToEthereum>await ethers.getContract("FastBridgeSenderToEthereum");
    homeGateway = <HomeGatewayToEthereum>await ethers.getContract("HomeGatewayToEthereum");
    arbsys = <ArbSys>await ethers.getContract("ArbSys");
    inbox = <Inbox>await ethers.getContract("Inbox");
    // safeBridgeEth = <SafeBridgeReceiverOnEthereum>await ethers.getContract("SafeBridgeReceiverOnEthereum");
  });

  it("RNG", async () => {
    const rnOld = await ng.number();
    let tx = await ng.getRN(9876543210);
    let trace = await network.provider.send("debug_traceTransaction", [tx.hash]);
    let [rn] = ethers.utils.defaultAbiCoder.decode(["uint"], `0x${trace.returnValue}`);
    expect(rn).to.equal(rnOld);

    tx = await ng.getRN(9876543210);
    trace = await network.provider.send("debug_traceTransaction", [tx.hash]);
    [rn] = ethers.utils.defaultAbiCoder.decode(["uint"], `0x${trace.returnValue}`);
    expect(rn).to.equal(rnOld.add(1));
  });

  it("Demo - Honest Claim - Challenged", async () => {
    const arbitrationCost = ONE_TENTH_ETH.mul(3);
    const [bridger, challenger] = await ethers.getSigners();

    await pnk.approve(core.address, ONE_THOUSAND_PNK.mul(100));

    await core.setStake(0, ONE_THOUSAND_PNK);
    await core.getJurorBalance(deployer, 0).then((result) => {
      expect(result.staked).to.equal(ONE_THOUSAND_PNK);
      // expect(result.locked).to.equal(0); @note gives error
      logJurorBalance(result);
    });

    await core.setStake(0, ONE_HUNDRED_PNK.mul(5));
    await core.getJurorBalance(deployer, 0).then((result) => {
      expect(result.staked).to.equal(ONE_HUNDRED_PNK.mul(5));
      expect(result.locked).to.equal(0);
      logJurorBalance(result);
    });

    await core.setStake(0, 0);
    await core.getJurorBalance(deployer, 0).then((result) => {
      expect(result.staked).to.equal(0);
      expect(result.locked).to.equal(0);
      logJurorBalance(result);
    });

    await core.setStake(0, ONE_THOUSAND_PNK.mul(4));
    await core.getJurorBalance(deployer, 0).then((result) => {
      expect(result.staked).to.equal(ONE_THOUSAND_PNK.mul(4));
      expect(result.locked).to.equal(0);
      logJurorBalance(result);
    });
    const tx = await arbitrable.createDispute(2, "0x00", 0, { value: arbitrationCost }); // @note : creating dispute via arbitrable example
    const trace = await network.provider.send("debug_traceTransaction", [tx.hash]);
    const [disputeId] = ethers.utils.defaultAbiCoder.decode(["uint"], `0x${trace.returnValue}`);
    console.log("Dispute Created");
    expect(tx).to.emit(foreignGateway, "DisputeCreation"); //.withArgs(disputeId, deployer.address);
    expect(tx).to.emit(foreignGateway, "OutgoingDispute"); //.withArgs(disputeId, deployer.address);
    console.log(`disputeId: ${disputeId}`);

    let events = await foreignGateway.queryFilter(OutgoingMessage);


    const lastBlock = await ethers.provider.getBlock(tx.blockNumber - 1);
    const disputeHash = ethers.utils.solidityKeccak256(
      ["uint", "bytes", "bytes", "uint", "uint", "bytes", "address"],
      [31337, lastBlock.hash, ethers.utils.toUtf8Bytes("createDispute"), disputeId, 2, "0x00", arbitrable.address]
    );

    // Relayer tx
    const tx2 = await homeGateway
      .connect(await ethers.getSigner(relayer))
      .relayCreateDispute(31337, lastBlock.hash, disputeId, 2, "0x00", arbitrable.address, {
        value: arbitrationCost,
      });
    expect(tx2).to.emit(homeGateway, "Dispute");
    const events2 = (await tx2.wait()).events;
    // console.log("event=%O", events2);


    const tx3 = await core.draw(0, 1000);
    const events3 = (await tx3.wait()).events;
    // console.log("event=%O", events3[0].args);
    // console.log("event=%O", events3[1].args);
    // console.log("event=%O", events3[2].args);

    const roundInfo = await core.getRoundInfo(0, 0);
    expect(roundInfo.drawnJurors).deep.equal([deployer, deployer, deployer]);
    expect(roundInfo.tokensAtStakePerJuror).to.equal(ONE_HUNDRED_PNK.mul(2));
    expect(roundInfo.totalFeesForJurors).to.equal(arbitrationCost);

    expect((await core.disputes(0)).period).to.equal(Period.evidence);

    await core.passPeriod(0);
    expect((await core.disputes(0)).period).to.equal(Period.vote);
    await disputeKit.connect(await ethers.getSigner(deployer)).castVote(0, [0,1,2], 0, 0);
    await core.passPeriod(0);
    await core.passPeriod(0);
    expect((await core.disputes(0)).period).to.equal(Period.execution);
    await core.execute(0, 0, 1000);
    let ticket1 = await fastBridgeSender.currentTicketID();
    expect(ticket1).to.equal(1);


    const tx4 = await core.executeRuling(0);
    expect(tx4).to.emit(fastBridgeSender, "OutgoingMessage");

    let event4 = await fastBridgeSender.queryFilter(OutgoingMessage);
    let message = event4[0].args[4];  // @note : here we get the sendFast outgoing message 
    console.log("Executed ruling");

    let ticket2 = await fastBridgeSender.currentTicketID();
    expect(ticket2).to.equal(2);

    const ticketID = event4[0].args.ticketID;
    const messageHash = event4[0].args.messageHash;
    const blockNumber = event4[0].args.blockNumber;
    const messageData = event4[0].args.message;
    

    //bridger tx @note bridger tx starts
    const tx5 = await fastBridgeReceiver.connect(bridger).claim(ticketID, messageHash, {value : ONE_TENTH_ETH});
    let blockNumBefore = await ethers.provider.getBlockNumber();
    let blockBefore = await ethers.provider.getBlock(blockNumBefore);
    let timestampBefore = blockBefore.timestamp;
    expect(tx5).to.emit(fastBridgeReceiver,"ClaimReceived").withArgs(ticketID, messageHash, timestampBefore);

    //Challenger tx @note Challenger tx starts
    const tx6 = await fastBridgeReceiver.connect(challenger).challenge(ticketID, {value : ONE_TENTH_ETH});
     blockNumBefore = await ethers.provider.getBlockNumber();
     blockBefore = await ethers.provider.getBlock(blockNumBefore);
     timestampBefore = blockBefore.timestamp;

    console.log(ticketID, blockNumber.toNumber(), blockNumBefore, timestampBefore);

    expect(tx6).to.emit(fastBridgeReceiver,"ClaimChallenged").withArgs(ticketID, timestampBefore);
    const events6 = (await tx6.wait()).events;
    console.log(events6[0].args.ticketID.toNumber());
    console.log(events6[0].args.challengedAt.toNumber());
     
    //wait for challenge period to pass
    await network.provider.send("evm_increaseTime", [300]);
    await network.provider.send("evm_mine");    
    

    await expect(fastBridgeReceiver.connect(bridger).verifyAndRelay(ticketID, blockNumber, messageData)).to.be.revertedWith('Claim is challenged');

    await fastBridgeSender.set_arb(arbsys.address);

    let data = await ethers.utils.defaultAbiCoder.decode(["address", "bytes"], message);
    let tx7 = await fastBridgeSender.connect(bridger).sendSafeFallback(ticketID, foreignGateway.address, data[1],  { gasLimit: 1000000}
);
    expect(tx7).to.emit(fastBridgeSender, "L2ToL1TxCreated");
    expect(tx7).to.emit(arbitrable, "Ruling");
    console.log("ticketID is: %d", ticketID);

    // let bridgerBalance = await ethers.provider.getBalance(bridger.address);
    // console.log("Bridger Balance: %s",bridgerBalance.toString());

    const tx8 = await fastBridgeReceiver.withdrawClaimDeposit(ticketID);



    // const tx8 = await fastBridgeReceiver.withdrawChallengeDeposit(ticketID);
    await expect(fastBridgeReceiver.withdrawChallengeDeposit(ticketID)).to.be.revertedWith('Claim verified: deposit forfeited');
     
  });
});

const logJurorBalance = function (result) {
  console.log("staked=%s, locked=%s", ethers.utils.formatUnits(result.staked), ethers.utils.formatUnits(result.locked));
};