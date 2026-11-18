<template>
  <div>
    <h2 class="mb-4">OpenCode v2</h2>

    <v-skeleton-loader v-if="loading" :loading="true" type="card" />

    <div v-else style="margin-bottom: 80px">
      <v-alert
        v-if="error"
        type="error"
        variant="tonal"
        closable
        class="mb-4"
        @click:close="error = ''"
      >
        {{ error }}
      </v-alert>

      <!-- Status -->
      <v-card class="mb-4 pa-0">
        <v-card-title class="d-flex align-center">
          <v-icon class="mr-2">mdi-robot</v-icon>
          <span>Status</span>
          <v-spacer />
          <v-chip :color="running ? 'success' : 'grey'" size="small" variant="tonal">
            {{ statusText }}
          </v-chip>
        </v-card-title>
        <v-card-text>
          <v-row>
            <v-col cols="12" md="3">
              <div class="text-caption text-medium-emphasis">Installed</div>
              <div class="text-subtitle-1 font-weight-medium">{{ currentVersion || 'Not installed' }}</div>
            </v-col>
            <v-col cols="12" md="3">
              <div class="text-caption text-medium-emphasis">Latest</div>
              <div class="text-subtitle-1 font-weight-medium">{{ latestVersion || '-' }}</div>
            </v-col>
            <v-col cols="12" md="3">
              <div class="text-caption text-medium-emphasis">PID</div>
              <div class="text-subtitle-1 font-weight-medium">{{ running ? (pid || '-') : '-' }}</div>
            </v-col>
            <v-col cols="12" md="3">
              <div class="text-caption text-medium-emphasis">Service URL</div>
              <div class="text-subtitle-1 font-weight-medium text-truncate">{{ running ? webuiUrl : '-' }}</div>
            </v-col>
          </v-row>

          <div class="d-flex flex-wrap ga-2 mt-4">
            <v-btn size="small" variant="tonal" color="secondary" :loading="checkingUpdates" @click="checkForUpdates">
              Check updates
            </v-btn>
            <v-btn
              v-if="!currentVersion"
              size="small" color="primary"
              :loading="installing"
              :disabled="!settings.data_home"
              @click="doInstall"
            >
              Install
            </v-btn>
            <v-btn
              v-else-if="updateAvailable"
              size="small" color="primary"
              :loading="updating"
              @click="doUpdate"
            >
              Update to {{ latestVersion }}
            </v-btn>
            <v-btn
              v-if="currentVersion"
              size="small" color="error" variant="outlined"
              :loading="uninstalling"
              @click="uninstall"
            >
              Uninstall binary
            </v-btn>
          </div>

          <v-progress-linear v-if="installing || updating" indeterminate color="primary" class="mt-4" />
          <div v-if="installing || updating" class="text-caption text-medium-emphasis mt-2">
            Downloading in the background. You can leave this page; the installer keeps running.
          </div>
        </v-card-text>
      </v-card>

      <!-- Settings -->
      <v-card class="mb-4 pa-0">
        <v-card-title class="d-flex align-center">
          <v-icon class="mr-2">mdi-cog</v-icon>
          <span>Settings</span>
        </v-card-title>
        <v-card-text>
          <v-text-field
            v-model="settings.data_home"
            label="Data directory"
            hint="Persistent config, data and state for OpenCode"
            persistent-hint
            class="mt-2"
          >
            <template #append-inner>
              <v-btn size="small" icon="mdi-folder" variant="text" @click="openFsDialog" />
            </template>
          </v-text-field>

          <v-text-field
            v-model="settings.work_dir"
            label="Default working directory"
            hint="Where new OpenCode terminals start. Empty or missing paths fall back to /."
            persistent-hint
            class="mt-4"
          />

          <v-text-field
            v-model="settings.pin_version"
            label="Pin OpenCode version (optional)"
            hint="For example 2.3.2. Empty means the latest v2 release."
            persistent-hint
            class="mt-4"
            style="max-width: 260px"
          />

          <v-switch
            v-model="settings.auto_install"
            label="Download the binary automatically when missing"
            color="primary"
            inset
            hide-details
            class="mt-4"
          />

          <v-switch
            v-model="settings.auto_start"
            label="Start the server automatically after MOS services"
            color="primary"
            inset
            hide-details
            class="mt-2"
            :disabled="!settings.server_enabled"
          />

          <v-alert type="info" variant="tonal" density="compact" class="mt-4">
            OpenCode self-update and <code>/update</code> are disabled on MOS.
            Use the Install/Update buttons on this page. The plugin verifies the
            release SHA256 and keeps the version in the MOS plugin settings.
          </v-alert>

          <v-btn color="primary" class="mt-4" :loading="saving" @click="saveSettings">
            <v-icon start>mdi-content-save</v-icon>
            Save
          </v-btn>
        </v-card-text>
      </v-card>

      <!-- Server -->
      <v-card class="mb-4 pa-0">
        <v-card-title class="d-flex align-center">
          <v-icon class="mr-2">mdi-server-network</v-icon>
          <span>Server</span>
          <v-spacer />
          <v-chip :color="settings.server_enabled ? 'primary' : 'grey'" size="small" variant="tonal">
            {{ settings.server_enabled ? 'Enabled' : 'Off' }}
          </v-chip>
        </v-card-title>
        <v-card-text>
          <v-switch
            v-model="settings.server_enabled"
            label="Enable the OpenCode background server"
            color="primary"
            inset
            hide-details
          />
          <p class="text-body-2 text-medium-emphasis mt-2">
            Off by default. With the server off, no port is opened; the OpenCode TUI
            still works from an SSH terminal.
          </p>

          <template v-if="settings.server_enabled">
            <v-divider class="my-4" />
            <v-text-field
              v-model="settings.hostname"
              label="Service hostname"
              hint="127.0.0.1 is local only. Use 0.0.0.0 to listen on the LAN."
              persistent-hint
              style="max-width: 260px"
            />
            <v-text-field
              v-model="settings.port"
              label="Service port"
              hint="Default: 4096"
              persistent-hint
              type="number"
              class="mt-4"
              style="max-width: 200px"
            />
            <v-text-field
              v-model="settings.service_password"
              label="Service password (optional)"
              hint="Leave empty to keep an existing password or let OpenCode generate one."
              persistent-hint
              type="password"
              class="mt-4"
              style="max-width: 320px"
            />
            <v-text-field
              v-model="settings.service_cors"
              label="Service CORS origins (optional)"
              hint="Comma-separated origins, for example https://example.com."
              persistent-hint
              class="mt-4"
            />

            <div class="d-flex flex-wrap ga-2 mt-4">
              <v-btn size="small" color="primary" :disabled="!currentVersion || running" :loading="starting" @click="startServer">
                Start
              </v-btn>
              <v-btn size="small" color="error" variant="outlined" :disabled="!running" :loading="stopping" @click="stopServer">
                Stop
              </v-btn>
              <v-btn size="small" variant="tonal" :disabled="!currentVersion" :loading="restarting" @click="restartServer">
                Restart
              </v-btn>
              <v-btn v-if="running" size="small" variant="tonal" :href="webuiUrl" target="_blank">
                Open server
              </v-btn>
            </div>
            <p class="text-caption text-medium-emphasis mt-2">
              Service settings apply when the server starts or restarts. Save first, then Restart.
            </p>
          </template>
        </v-card-text>
      </v-card>

      <!-- Logs -->
      <v-card class="pa-0">
        <v-card-title class="d-flex align-center">
          <v-icon class="mr-2">mdi-text-box-outline</v-icon>
          <span>Logs</span>
          <v-spacer />
          <v-btn size="small" variant="text" :loading="loadingLogs" @click="loadLogs">Refresh</v-btn>
        </v-card-title>
        <v-card-text>
          <pre class="opencode-log">{{ logs || 'No log output yet.' }}</pre>
        </v-card-text>
      </v-card>
    </div>

    <!-- File System Dialog -->
    <v-dialog v-model="fsDialog" max-width="800">
      <v-card>
        <v-card-title class="d-flex align-center">
          <span>Select data directory</span>
          <v-spacer />
          <v-chip size="small" class="ml-2" variant="tonal">{{ fsCurrentPath || '/' }}</v-chip>
        </v-card-title>
        <v-card-subtitle class="pb-0">
          <div class="d-flex align-center ga-2">
            <v-btn size="small" variant="text" icon="mdi-home" @click="fsGoRoot" color="secondary" :disabled="fsLoading" />
            <v-btn size="small" variant="text" icon="mdi-arrow-up" @click="fsNavigateUp" color="secondary" :disabled="fsCurrentPath === '/mnt' || fsLoading" />
            <v-btn size="small" variant="text" icon="mdi-refresh" @click="fetchDirectory(fsCurrentPath)" color="secondary" :disabled="fsLoading" />
            <v-spacer />
            <v-progress-circular v-if="fsLoading" indeterminate size="20" color="secondary" />
          </div>
        </v-card-subtitle>
        <v-card-text class="pt-2" style="min-height: 300px; max-height: 60vh; overflow-y: auto">
          <v-table density="compact">
            <thead>
              <tr>
                <th>Name</th>
                <th style="width: 40%">Path</th>
                <th style="width: 60px" class="text-center">Action</th>
              </tr>
            </thead>
            <tbody>
              <tr v-if="!fsLoading && fsItems.length === 0">
                <td colspan="3" class="text-center text-medium-emphasis">No entries</td>
              </tr>
              <tr
                v-for="item in fsItems"
                :key="item.path"
                :class="['cursor-pointer', fsActiveItem && fsActiveItem.path === item.path ? 'bg-primary bg-opacity-10' : '']"
                @click="fsActiveItem = item"
                @dblclick.stop.prevent="fsNavigateInto(item)"
              >
                <td>
                  <div class="d-flex align-center ga-2">
                    <v-icon size="18">mdi-folder</v-icon>
                    <span>{{ item.name }}</span>
                  </div>
                </td>
                <td><span class="text-caption">{{ item.displayPath || item.path }}</span></td>
                <td class="text-center">
                  <v-btn size="small" icon="mdi-folder-open" variant="text" @click.stop="fsNavigateInto(item)" :disabled="fsLoading" />
                </td>
              </tr>
            </tbody>
          </v-table>
        </v-card-text>
        <v-divider />
        <v-card-actions class="d-flex align-center">
          <div class="text-caption text-truncate" style="max-width: 60%">
            <strong>Selected:</strong>
            <span v-if="fsActiveItem">{{ fsActiveItem.displayPath || fsActiveItem.path }}</span>
            <span v-else>-</span>
          </div>
          <v-spacer />
          <v-btn variant="text" @click="fsDialog = false">Cancel</v-btn>
          <v-btn color="primary" @click="fsSelect" :disabled="fsLoading">Select</v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <v-snackbar v-model="snackbar" :color="snackbarColor" timeout="4000">
      {{ snackbarText }}
    </v-snackbar>
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted, onUnmounted } from 'vue';

const PLUGIN_NAME = 'opencode-v2';

const DEFAULT_SETTINGS = {
  auto_start: true,
  auto_install: true,
  server_enabled: false,
  hostname: '127.0.0.1',
  port: '4096',
  data_home: '',
  work_dir: '',
  version: '',
  pin_version: '',
  service_password: '',
  service_cors: '',
};

const loading = ref(true);
const saving = ref(false);
const installing = ref(false);
const updating = ref(false);
const uninstalling = ref(false);
const checkingUpdates = ref(false);
const starting = ref(false);
const stopping = ref(false);
const restarting = ref(false);
const loadingLogs = ref(false);
const fsDialog = ref(false);
const fsCurrentPath = ref('');
const fsItems = ref([]);
const fsLoading = ref(false);
const fsActiveItem = ref(null);

const running = ref(false);
const pid = ref(0);
const currentVersion = ref('');
const latestVersion = ref('');
const updateAvailable = ref(false);
const logs = ref('');
const error = ref('');
const statusInterval = ref(null);

const snackbar = ref(false);
const snackbarText = ref('');
const snackbarColor = ref('success');

const settings = reactive({ ...DEFAULT_SETTINGS });

const statusText = computed(() => {
  if (!settings.server_enabled) return 'Server off';
  return running.value ? 'Running' : 'Stopped';
});

const webuiUrl = computed(() => {
  const port = settings.port || '4096';
  const host =
    settings.hostname && settings.hostname !== '0.0.0.0'
      ? settings.hostname
      : window.location.hostname;
  return `http://${host}:${port}`;
});

const getAuthHeaders = () => ({
  Authorization: 'Bearer ' + localStorage.getItem('authToken'),
});

const toast = (text, color = 'success') => {
  snackbarText.value = text;
  snackbarColor.value = color;
  snackbar.value = true;
};

const queryPlugin = async (args, parseJson = true, timeout = 10) => {
  const res = await fetch('/api/v1/mos/plugins/query', {
    method: 'POST',
    headers: {
      ...getAuthHeaders(),
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      command: PLUGIN_NAME,
      args,
      timeout,
      parse_json: parseJson,
    }),
  });
  if (!res.ok) throw new Error('Plugin command failed');
  const data = await res.json();
  if (!data.success) {
    throw new Error(typeof data.output === 'string' ? data.output : 'Plugin command failed');
  }
  return data.output;
};

const postSettings = async (version = currentVersion.value) => {
  const res = await fetch(`/api/v1/mos/plugins/settings/${PLUGIN_NAME}`, {
    method: 'POST',
    headers: {
      ...getAuthHeaders(),
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      ...settings,
      version: version || '',
    }),
  });
  if (!res.ok) throw new Error('Failed to save settings');
};

const waitForInstall = async () => {
  for (let i = 0; i < 900; i += 1) {
    await new Promise((resolve) => setTimeout(resolve, 2000));
    const out = await queryPlugin(['install_status'], true, 10);
    if (out && out.state === 'done') return out;
    if (out && out.state === 'failed') throw new Error(out.error || 'Install failed');
  }
  throw new Error('Install timed out');
};

const fetchSettings = async () => {
  try {
    const res = await fetch(`/api/v1/mos/plugins/settings/${PLUGIN_NAME}`, {
      headers: getAuthHeaders(),
    });
    if (res.ok) {
      const data = await res.json();
      for (const key of Object.keys(DEFAULT_SETTINGS)) {
        if (data[key] !== undefined) settings[key] = data[key];
      }
      if (data.version) currentVersion.value = data.version;
    }
  } catch (e) {
    console.error('Failed to fetch settings:', e);
    error.value = 'Failed to load plugin settings.';
  }
};

const checkStatus = async () => {
  try {
    const out = await queryPlugin(['status'], true, 10);
    running.value = out.running === true;
    pid.value = out.pid || 0;
  } catch (e) {
    console.error('Failed to read status:', e);
    running.value = false;
  }
};

const checkForUpdates = async () => {
  checkingUpdates.value = true;
  try {
    const out = await queryPlugin(['check_version'], true, 20);
    latestVersion.value = out.latest || '';
    updateAvailable.value = Boolean(currentVersion.value) && out.update_available === true;
  } catch (e) {
    console.error('Failed to check updates:', e);
    toast(e.message || 'Failed to check updates', 'error');
  } finally {
    checkingUpdates.value = false;
  }
};

const saveSettings = async () => {
  saving.value = true;
  try {
    await postSettings();
    if (!settings.server_enabled && running.value) {
      await queryPlugin(['stop'], false, 30);
    }
    await checkStatus();
    toast('Settings saved');
  } catch (e) {
    console.error('Failed to save settings:', e);
    toast(e.message || 'Failed to save settings', 'error');
  } finally {
    saving.value = false;
  }
};

const doInstall = async () => {
  installing.value = true;
  try {
    if (!settings.data_home) {
      toast('Set a data directory first', 'error');
      return;
    }
    await postSettings('');
    currentVersion.value = '';
    await queryPlugin(['install_binary'], false, 15);
    await waitForInstall();
    await fetchSettings();
    await checkStatus();
    await checkForUpdates();
    toast('OpenCode installed');
  } catch (e) {
    console.error('Failed to install:', e);
    toast(e.message || 'Install failed', 'error');
  } finally {
    installing.value = false;
  }
};

const doUpdate = async () => {
  updating.value = true;
  try {
    await postSettings();
    await queryPlugin(['install_binary'], false, 15);
    await waitForInstall();
    await fetchSettings();
    await checkStatus();
    await checkForUpdates();
    toast('OpenCode updated');
  } catch (e) {
    console.error('Failed to update:', e);
    toast(e.message || 'Update failed', 'error');
  } finally {
    updating.value = false;
  }
};

const uninstall = async () => {
  if (!window.confirm('Remove the OpenCode binary? Config, data and sessions are kept.')) return;
  uninstalling.value = true;
  try {
    await queryPlugin(['uninstall'], false, 30);
    currentVersion.value = '';
    updateAvailable.value = false;
    await checkStatus();
    toast('OpenCode binary removed');
  } catch (e) {
    console.error('Failed to uninstall:', e);
    toast(e.message || 'Uninstall failed', 'error');
  } finally {
    uninstalling.value = false;
  }
};

const startServer = async () => {
  starting.value = true;
  try {
    await postSettings();
    await queryPlugin(['start'], false, 30);
    await checkStatus();
  } catch (e) {
    console.error('Failed to start server:', e);
    toast(e.message || 'Failed to start server', 'error');
  } finally {
    starting.value = false;
  }
};

const stopServer = async () => {
  stopping.value = true;
  try {
    await queryPlugin(['stop'], false, 30);
    await checkStatus();
  } catch (e) {
    console.error('Failed to stop server:', e);
    toast(e.message || 'Failed to stop server', 'error');
  } finally {
    stopping.value = false;
  }
};

const restartServer = async () => {
  restarting.value = true;
  try {
    await postSettings();
    await queryPlugin(['restart'], false, 30);
    await checkStatus();
  } catch (e) {
    console.error('Failed to restart server:', e);
    toast(e.message || 'Failed to restart server', 'error');
  } finally {
    restarting.value = false;
  }
};

const loadLogs = async () => {
  loadingLogs.value = true;
  try {
    const out = await queryPlugin(['logs', '200'], false, 10);
    logs.value = typeof out === 'string' ? out : JSON.stringify(out, null, 2);
  } catch (e) {
    console.error('Failed to load logs:', e);
    toast(e.message || 'Failed to load logs', 'error');
  } finally {
    loadingLogs.value = false;
  }
};

const openFsDialog = async () => {
  fsCurrentPath.value = settings.data_home || '/mnt';
  fsDialog.value = true;
  await fetchDirectory(fsCurrentPath.value);
};

const fetchDirectory = async (dirPath) => {
  fsLoading.value = true;
  fsActiveItem.value = null;
  try {
    const url = new URL('/api/v1/mos/fsnavigator', window.location.origin);
    if (dirPath && dirPath !== '/') {
      url.searchParams.set('path', dirPath);
    }
    url.searchParams.set('type', 'directories');
    url.searchParams.set('roots', '/mnt');

    const res = await fetch(url.toString(), { headers: getAuthHeaders() });
    if (res.ok) {
      const data = await res.json();
      fsCurrentPath.value = data.currentPath || dirPath || '/mnt';
      fsItems.value = Array.isArray(data.items) ? data.items : [];
    } else {
      fsItems.value = [];
    }
  } catch (e) {
    console.error('Failed to fetch directory:', e);
    fsItems.value = [];
  } finally {
    fsLoading.value = false;
  }
};

const fsNavigateInto = (item) => {
  if (!item || item.type !== 'directory') return;
  fetchDirectory(item.path);
};

const fsNavigateUp = () => {
  if (!fsCurrentPath.value || fsCurrentPath.value === '/mnt') return;
  const parts = fsCurrentPath.value.split('/').filter(Boolean);
  parts.pop();
  fetchDirectory('/' + parts.join('/') || '/mnt');
};

const fsGoRoot = () => {
  fetchDirectory('/mnt');
};

const fsSelect = () => {
  if (fsActiveItem.value) {
    settings.data_home = fsActiveItem.value.path;
  } else {
    settings.data_home = fsCurrentPath.value;
  }
  fsDialog.value = false;
};

onMounted(async () => {
  try {
    await fetchSettings();
    await checkStatus();
    if (!currentVersion.value) {
      checkForUpdates();
    }

    queryPlugin(['install_status'], true, 10)
      .then((out) => {
        if (out && out.state === 'running') {
          installing.value = true;
          waitForInstall()
            .then(() => Promise.all([fetchSettings(), checkStatus(), checkForUpdates()]))
            .catch((e) => console.error('Background install failed:', e))
            .finally(() => {
              installing.value = false;
            });
        }
      })
      .catch(() => {});

    statusInterval.value = setInterval(checkStatus, 5000);
  } catch (e) {
    console.error('Failed to initialize:', e);
  } finally {
    loading.value = false;
  }
});

onUnmounted(() => {
  if (statusInterval.value) clearInterval(statusInterval.value);
});
</script>

<style scoped>
.opencode-log {
  max-height: 360px;
  overflow: auto;
  white-space: pre-wrap;
  word-break: break-word;
  font-size: 12px;
  line-height: 1.45;
  background: rgba(0, 0, 0, 0.25);
  border-radius: 6px;
  padding: 12px;
  margin: 0;
}
</style>