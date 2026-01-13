/// Shared chat page JavaScript for both Flutter and CLI modes
/// No Flutter dependencies - pure Dart only

/// Get JavaScript for chat page interactivity
/// Used by:
/// - WebThemeService (Flutter apps, device chat pages)
/// - PureStationServer (CLI mode, station chat page)
String getChatPageScripts() {
  return '''
    (function() {
      const data = window.GEOGRAM_DATA || {};
      let currentRoom = data.currentRoom || 'main';
      let lastTimestamp = null;
      let pollInterval = null;

      function initChannels() {
        document.querySelectorAll('.channel-item').forEach(item => {
          item.addEventListener('click', function() {
            const roomId = this.dataset.roomId;
            switchRoom(roomId);
          });
        });
      }

      function switchRoom(roomId) {
        if (roomId === currentRoom && lastTimestamp !== null) return;
        currentRoom = roomId;
        lastTimestamp = null;

        document.querySelectorAll('.channel-item').forEach(item => {
          item.classList.toggle('active', item.dataset.roomId === roomId);
        });

        document.getElementById('current-room').textContent = roomId;
        document.getElementById('messages').innerHTML = '<div class="status-message">Loading messages...</div>';
        loadMessages();
      }

      async function loadMessages() {
        try {
          const url = data.apiBasePath + '/' + encodeURIComponent(currentRoom) + '/messages';
          const response = await fetch(url);
          if (!response.ok) {
            document.getElementById('messages').innerHTML = '<div class="empty-state">Failed to load messages</div>';
            return;
          }

          const result = await response.json();
          let messages = [];
          if (Array.isArray(result)) {
            messages = result;
          } else if (result && Array.isArray(result.messages)) {
            messages = result.messages;
          }

          const container = document.getElementById('messages');
          container.innerHTML = '';

          if (messages.length === 0) {
            container.innerHTML = '<div class="empty-state">No messages yet</div>';
            return;
          }

          let currentDate = null;
          messages.forEach(msg => {
            const msgDate = msg.timestamp.split(' ')[0];
            if (currentDate !== msgDate) {
              currentDate = msgDate;
              const sep = document.createElement('div');
              sep.className = 'date-separator';
              sep.textContent = msgDate;
              container.appendChild(sep);
            }
            appendMessage(msg);
            lastTimestamp = msg.timestamp;
          });

          scrollToBottom(true);
        } catch (e) {
          console.error('Error loading messages:', e);
          document.getElementById('messages').innerHTML = '<div class="empty-state">Error loading messages</div>';
        }
      }

      function appendMessage(msg) {
        const container = document.getElementById('messages');
        const div = document.createElement('div');
        div.className = 'message';
        div.dataset.timestamp = msg.timestamp;

        const timeParts = msg.timestamp.split(' ');
        const time = timeParts.length > 1 ? timeParts[1].replace('_', ':').substring(0, 5) : '00:00';
        const author = msg.author || msg.senderCallsign || 'anonymous';
        const content = msg.content || '';

        div.innerHTML = '<div class="message-header">' +
                       '<span class="message-author">' + escapeHtml(author) + '</span>' +
                       '<span class="message-time">' + time + '</span>' +
                       '</div>' +
                       '<div class="message-content">' + escapeHtml(content) + '</div>';

        container.appendChild(div);
      }

      async function pollNewMessages() {
        if (!lastTimestamp) return;

        try {
          const url = data.apiBasePath + '/' + encodeURIComponent(currentRoom) + '/messages?after=' + encodeURIComponent(lastTimestamp);
          const response = await fetch(url);
          if (!response.ok) return;

          const result = await response.json();
          let messages = [];
          if (Array.isArray(result)) {
            messages = result;
          } else if (result && Array.isArray(result.messages)) {
            messages = result.messages;
          }

          if (messages.length > 0) {
            const shouldScroll = isNearBottom();
            messages.forEach(msg => {
              if (msg.timestamp > lastTimestamp) {
                appendMessage(msg);
                lastTimestamp = msg.timestamp;
              }
            });
            if (shouldScroll) scrollToBottom(true);
          }
        } catch (e) {
          console.error('Error polling messages:', e);
        }
      }

      function escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
      }

      function startPolling() {
        if (pollInterval) clearInterval(pollInterval);
        pollInterval = setInterval(pollNewMessages, 5000);
      }

      function isNearBottom() {
        const container = document.getElementById('messages');
        if (!container) return true;
        const threshold = 100;
        return container.scrollHeight - container.scrollTop - container.clientHeight < threshold;
      }

      function scrollToBottom(force) {
        const container = document.getElementById('messages');
        if (container && (force || isNearBottom())) {
          container.scrollTop = container.scrollHeight;
        }
      }

      document.addEventListener('DOMContentLoaded', function() {
        initChannels();
        scrollToBottom(true);
        startPolling();
      });
    })();
  ''';
}
