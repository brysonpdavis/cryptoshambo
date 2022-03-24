import {ethers} from 'ethers'
import axios from 'axios'
import Web3Modal from 'web3modal'

import {useState, useEffect} from 'react'

import {cryptoshamboaddress} from '../config'

import Cryptoshambo from '../artifacts/contracts/Cryptoshambo.sol/Cryptoshambo.json'
console.log(Cryptoshambo.abi)
export default function Home() {
  const [games, setGames] = useState([])
  const [loadingState, setLoadingState] = useState('not-loaded')

  useEffect(() =>  {
    try{loadWagers()}
    catch(error) {
      console.log(error)
    } 
    
  }, []
  )

  async function loadWagers() {
    setLoadingState('not-loaded')
    const web3modal = new Web3Modal()
    const connection = await web3modal.connect()
    const provider = new ethers.providers.Web3Provider(connection)
    const contract = new ethers.Contract(cryptoshamboaddress, Cryptoshambo.abi, provider)
    const data = await contract.getLatestWagers()

    const items = await Promise.all(data.map(async i => {
      console.log(i)
      return i
    }))

    setGames(items)
    setLoadingState('loaded')
  }
  return (
    <div>
      welcome home
      {games}
    </div>
  )
}

// to do: create form to submit wagers
// to do: option to cancel a wager if it belongs to you
// to do: option to see all wagers from your own address
// to do: add in web3ui library from dev_dao and add a wallet connect button