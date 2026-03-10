package com.example.royalvncandroidtest

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Log
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

data class DiscoveredServer(
    val name: String,
    val hostname: String,
    val port: Int
)

class NsdBrowser(context: Context) {
    private val nsdManager = context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val _servers = MutableStateFlow<List<DiscoveredServer>>(emptyList())
    val servers: StateFlow<List<DiscoveredServer>> = _servers
    private var isDiscovering = false

    private val discoveryListener = object : NsdManager.DiscoveryListener {
        override fun onDiscoveryStarted(serviceType: String) {
            Log.d("NsdBrowser", "Discovery started")
        }

        override fun onDiscoveryStopped(serviceType: String) {
            Log.d("NsdBrowser", "Discovery stopped")
            isDiscovering = false
        }

        override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
            Log.e("NsdBrowser", "Discovery start failed: $errorCode")
            isDiscovering = false
        }

        override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
            Log.e("NsdBrowser", "Discovery stop failed: $errorCode")
        }

        override fun onServiceFound(serviceInfo: NsdServiceInfo) {
            Log.d("NsdBrowser", "Service found: ${serviceInfo.serviceName}")
            nsdManager.resolveService(serviceInfo, createResolveListener())
        }

        override fun onServiceLost(serviceInfo: NsdServiceInfo) {
            Log.d("NsdBrowser", "Service lost: ${serviceInfo.serviceName}")
            _servers.value = _servers.value.filter { it.name != serviceInfo.serviceName }
        }
    }

    private fun createResolveListener() = object : NsdManager.ResolveListener {
        override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
            Log.e("NsdBrowser", "Resolve failed for ${serviceInfo.serviceName}: $errorCode")
        }

        override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
            val hostAddress = serviceInfo.host?.hostAddress ?: return
            val server = DiscoveredServer(
                name = serviceInfo.serviceName,
                hostname = hostAddress,
                port = serviceInfo.port
            )
            Log.d("NsdBrowser", "Resolved: ${server.name} -> ${server.hostname}:${server.port}")
            _servers.value = _servers.value.filter { it.name != server.name } + server
        }
    }

    fun startDiscovery() {
        if (isDiscovering) return
        isDiscovering = true
        _servers.value = emptyList()
        nsdManager.discoverServices("_rfb._tcp", NsdManager.PROTOCOL_DNS_SD, discoveryListener)
    }

    fun stopDiscovery() {
        if (!isDiscovering) return
        try {
            nsdManager.stopServiceDiscovery(discoveryListener)
        } catch (e: Exception) {
            Log.e("NsdBrowser", "Error stopping discovery: ${e.message}")
        }
        isDiscovering = false
    }
}
