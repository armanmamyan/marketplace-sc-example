const API_URL = "https://eth-goerli.g.alchemy.com/v2/API_KEY";
const PRIVATE_KEY = "PRIVATE_KEY";
const { createAlchemyWeb3 } = require("@alch/alchemy-web3");
const web3 = createAlchemyWeb3(API_URL);

const cancelTx = async () => {
    const myAddress = "";
    const nonce = await web3.eth.getTransactionCount(myAddress, "latest");


  const transaction = {
    gas: "53000",
    maxPriorityFeePerGas: "2000000180",
    nonce: 158,
  };
  const replacementTx = {
    gas: "930000",
    maxPriorityFeePerGas: "110000010080",
    nonce: 158,
  };

  const signedTx = await web3.eth.accounts.signTransaction(
    transaction,
    PRIVATE_KEY
  );
  const signedReplacementTx = await web3.eth.accounts.signTransaction(
    replacementTx,
    PRIVATE_KEY
  );

  web3.eth.sendSignedTransaction(
    signedTx.rawTransaction,
    function (error, hash) {
      if (!error) {
        console.log(
          "The hash of the transaction we are going to cancel is: ",
          hash
        );
      } else {
        console.log(
          "Something went wrong while submitting your transaction:",
          error
        );
      }
    }
  );

  web3.eth
    .sendSignedTransaction(
      signedReplacementTx.rawTransaction,
      function (error, hash) {
        if (!error) {
          console.log(
            "The hash of your replacement transaction is: ",
            hash,
            "\n Check Alchemy's Mempool to view the status of your transactions!"
          );
        } else {
          console.log(
            "Something went wrong while submitting your replacement transaction:",
            error
          );
        }
      }
    )
    .once("sent", () => {
      let timeout = new Promise(() => {
        let id = setTimeout(() => {
          clearTimeout(id);
          process.exit();
        }, 3000);
      });
      return timeout;
    });
};

cancelTx();
