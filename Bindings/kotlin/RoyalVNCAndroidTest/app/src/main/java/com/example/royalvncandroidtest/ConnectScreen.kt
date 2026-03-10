package com.example.royalvncandroidtest

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.flow.StateFlow

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConnectScreen(
    discoveredServers: StateFlow<List<DiscoveredServer>>,
    profileStore: ProfileStore,
    onConnect: (String, Int) -> Unit,
    onSettings: () -> Unit
) {
    val servers by discoveredServers.collectAsState()
    var profiles by remember { mutableStateOf(profileStore.loadProfiles()) }

    var hostname by remember { mutableStateOf("") }
    var port by remember { mutableStateOf("5900") }
    var showAddProfile by remember { mutableStateOf(false) }
    var profileName by remember { mutableStateOf("") }
    var profileHost by remember { mutableStateOf("") }
    var profilePort by remember { mutableStateOf("5900") }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("RoyalVNC") },
                actions = {
                    IconButton(onClick = onSettings) {
                        Icon(Icons.Default.Settings, contentDescription = "Settings")
                    }
                }
            )
        },
        floatingActionButton = {
            FloatingActionButton(onClick = { showAddProfile = true }) {
                Icon(Icons.Default.Add, contentDescription = "Save Profile")
            }
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            // Quick Connect
            item {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text("Quick Connect", style = MaterialTheme.typography.titleMedium)
                        Spacer(Modifier.height(8.dp))
                        OutlinedTextField(
                            value = hostname,
                            onValueChange = { hostname = it },
                            label = { Text("Hostname or IP") },
                            modifier = Modifier.fillMaxWidth(),
                            singleLine = true
                        )
                        Spacer(Modifier.height(8.dp))
                        OutlinedTextField(
                            value = port,
                            onValueChange = { port = it },
                            label = { Text("Port") },
                            modifier = Modifier.fillMaxWidth(),
                            singleLine = true
                        )
                        Spacer(Modifier.height(12.dp))
                        Button(
                            onClick = {
                                val p = port.toIntOrNull() ?: 5900
                                if (hostname.isNotBlank()) {
                                    onConnect(hostname.trim(), p)
                                }
                            },
                            modifier = Modifier.fillMaxWidth(),
                            enabled = hostname.isNotBlank()
                        ) {
                            Text("Connect")
                        }
                    }
                }
            }

            // Discovered Servers
            if (servers.isNotEmpty()) {
                item {
                    Spacer(Modifier.height(8.dp))
                    Text("Nearby Servers", style = MaterialTheme.typography.titleMedium)
                }

                items(servers, key = { it.name }) { server ->
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onConnect(server.hostname, server.port) }
                    ) {
                        Row(
                            modifier = Modifier
                                .padding(16.dp)
                                .fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(
                                Icons.Default.Search,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary
                            )
                            Spacer(Modifier.width(12.dp))
                            Column(modifier = Modifier.weight(1f)) {
                                Text(server.name, style = MaterialTheme.typography.bodyLarge)
                                Text(
                                    "${server.hostname}:${server.port}",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }
                }
            }

            // Saved Profiles
            if (profiles.isNotEmpty()) {
                item {
                    Spacer(Modifier.height(8.dp))
                    Text("Saved Profiles", style = MaterialTheme.typography.titleMedium)
                }

                items(profiles, key = { it.id }) { profile ->
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onConnect(profile.hostname, profile.port) }
                    ) {
                        Row(
                            modifier = Modifier
                                .padding(16.dp)
                                .fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(
                                Icons.Default.Star,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary
                            )
                            Spacer(Modifier.width(12.dp))
                            Column(modifier = Modifier.weight(1f)) {
                                Text(profile.name, style = MaterialTheme.typography.bodyLarge)
                                Text(
                                    "${profile.hostname}:${profile.port}",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                            IconButton(onClick = {
                                profileStore.removeProfile(profile.id)
                                profiles = profileStore.loadProfiles()
                            }) {
                                Icon(
                                    Icons.Default.Delete,
                                    contentDescription = "Delete",
                                    tint = MaterialTheme.colorScheme.error
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    // Add Profile Dialog
    if (showAddProfile) {
        AlertDialog(
            onDismissRequest = { showAddProfile = false },
            title = { Text("Save Profile") },
            text = {
                Column {
                    OutlinedTextField(
                        value = profileName,
                        onValueChange = { profileName = it },
                        label = { Text("Name") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                    Spacer(Modifier.height(8.dp))
                    OutlinedTextField(
                        value = profileHost,
                        onValueChange = { profileHost = it },
                        label = { Text("Hostname or IP") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                    Spacer(Modifier.height(8.dp))
                    OutlinedTextField(
                        value = profilePort,
                        onValueChange = { profilePort = it },
                        label = { Text("Port") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        if (profileName.isNotBlank() && profileHost.isNotBlank()) {
                            profileStore.addProfile(
                                ServerProfile(
                                    name = profileName.trim(),
                                    hostname = profileHost.trim(),
                                    port = profilePort.toIntOrNull() ?: 5900
                                )
                            )
                            profiles = profileStore.loadProfiles()
                            profileName = ""
                            profileHost = ""
                            profilePort = "5900"
                            showAddProfile = false
                        }
                    },
                    enabled = profileName.isNotBlank() && profileHost.isNotBlank()
                ) {
                    Text("Save")
                }
            },
            dismissButton = {
                TextButton(onClick = { showAddProfile = false }) {
                    Text("Cancel")
                }
            }
        )
    }
}
