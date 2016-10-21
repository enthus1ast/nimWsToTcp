#
#
#              Websocket to tcp proxy
#               (c) Copyright 2016 
#             David Krause, Tobias Freitag
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#
## This is an asyn websocket to tcp transport,
## Atm this is capable of tunneling a line based protocol (namely IRC)
## Everything else is not tested.


import asyncnet, asyncdispatch, websocket, asynchttpserver

type Host = tuple[host: string, port: Port]

proc pumpWsToTcp(req: Request, endpointSocket: AsyncSocket): Future[void] {.async.} =
  var fromWs: tuple[opcode: Opcode, data: string]
  while true:

    try:
      fromWs = await req.client.readData(false)
    except:
      return
    echo "ws: " & fromWs.data
    if fromWs.data == "":
      raise

    try:
      await endpointSocket.send(fromWs.data)
    except:
      # break
      raise

proc pumpTcpToWs(req: Request, endpointSocket: AsyncSocket): Future[void] {.async.} =
  var fromEndpoint: string = ""
  while true:    
    try:
      fromEndpoint = await endpointSocket.recvLine()
    except:
      return

    echo "endpoint: " & fromEndpoint
    if fromEndpoint == "":
      return

    try:
      await req.client.sendText(fromEndpoint,false)
    except:
      echo "pumpTcpToWs client socket is fuckd"
      return

proc processClientWebsocket(req: Request, src, dst: Host, page: string) {.async.} =
  let (success, error) = await(verifyWebsocketRequest(req, "irc"))
  if not success:
    if req.url.path == "/":
      echo "Deliver TWIRC - Tiny Web IRC Client"
      asyncCheck req.respond(Http200, readFile(page) )
    req.client.close()
  else:
    echo "New websocket customer arrived!"
    var endpointSocket: AsyncSocket = newAsyncSocket()
    try:
      await endpointSocket.connect(dst.host, dst.port)
      echo "Connected to endpoint"
      asyncCheck pumpWsToTcp(req, endpointSocket)
      asyncCheck pumpTcpToWs(req, endpointSocket) 
    except:
      echo "Could not connect to endpoint :("
      asyncCheck req.client.sendText("Could not connect to endpoint :(\n",false)
      echo "Closeing ws and tcp socket after error..."

      req.client.close()
      endpointSocket.close()

proc proxy * (src, dst: Host ,page = "info.html") =
  ## Proxy line by line based protocols between ws://src and tcp://dst
  ## `page` gets read from the filesystem when connection is not websocket
  var websocketServer = newAsyncHttpServer()
  proc paramHelper(req: Request) {.async.} = 
    try:
      asyncCheck processClientWebsocket(req, src, dst, page) 
    except:
      echo "processClientWebsocket is fuckd"
  asyncCheck websocketServer.serve(src.port, paramHelper)

when isMainModule:
  # proxy( ("0.0.0.0",Port(7788)), ("127.0.0.1",Port(6667)), page = "twirc.html" )
  # proxy( ("0.0.0.0",Port(7787)), ("irc.freenode.net",Port(6667)), page = "twirc.html" )
  proxy( ("0.0.0.0",Port(7787)), ("127.0.0.1",Port(6667)), page = "twirc.html" )
  runForever()
  