import React, { FC, useEffect, useState, useCallback } from 'react'
import useApi from '../hooks/useApi'
import useAccount from '../hooks/useAccount'
import useWebsocket from './useWebsocket'

import {
  ISession,
  WEBSOCKET_EVENT_TYPE_SESSION_UPDATE,
} from '../types'

export const useSession = (session_id: string) => {
  const api = useApi()
  const account = useAccount()

  const [ data, setData ] = useState<ISession>()

  const loadSession = useCallback(async (id: string) => {
    const result = await api.get<ISession>(`/api/v1/sessions/${id}`)
    if(!result) return
    setData(result)
  }, [])
  
  const reload = useCallback(() => {
    if(!session_id) return
    loadSession(session_id)
  }, [
    session_id,
    loadSession,
  ])

  useEffect(() => {
    if(!account.user) return
    if(session_id) {
      loadSession(session_id)
      return  
    } else {
      setData(undefined)
    }
  }, [
    account.user,
    session_id,
  ])

  useWebsocket(session_id, (parsedData) => {
    if(parsedData.type === WEBSOCKET_EVENT_TYPE_SESSION_UPDATE && parsedData.session) {
      const newSession: ISession = parsedData.session
      setData(newSession)
    }
  })

  return {
    data,
    reload,
  }
}

export default useSession