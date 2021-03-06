// Copyright (c) The Dijets Core Contributors
// SPDX-License-Identifier: Apache-2.0

//! `conn_notifs_channel` is a channel which delivers to the receiver only the last of N
//! messages that might have been sent by sender(s) since the last poll. The items are separated
//! using a key that is provided by the sender with each message.
//!
//! It provides an mpsc channel which has two ends `conn_notifs_channel::Receiver`
//! and `conn_notifs_channel::Sender` which behave similarly to existing mpsc data structures.

use crate::peer_manager::ConnectionNotification;
use channel::{dijets_channel, message_queues::QueueStyle};
use dijets_types::PeerId;

pub type Sender = dijets_channel::Sender<PeerId, ConnectionNotification>;
pub type Receiver = dijets_channel::Receiver<PeerId, ConnectionNotification>;

pub fn new() -> (Sender, Receiver) {
    dijets_channel::new(QueueStyle::LIFO, 1, None)
}

#[cfg(test)]
mod test {
    use super::*;
    use crate::{peer::DisconnectReason, transport::ConnectionMetadata};
    use dijets_config::network_id::NetworkContext;
    use futures::{executor::block_on, future::FutureExt, stream::StreamExt};

    fn send_new_peer(sender: &mut Sender, peer_id: PeerId) {
        let notif = ConnectionNotification::NewPeer(
            ConnectionMetadata::mock(peer_id),
            NetworkContext::mock(),
        );
        sender.push(peer_id, notif).unwrap()
    }

    fn send_lost_peer(sender: &mut Sender, peer_id: PeerId, reason: DisconnectReason) {
        let notif = ConnectionNotification::LostPeer(
            ConnectionMetadata::mock(peer_id),
            NetworkContext::mock_with_peer_id(peer_id),
            reason,
        );
        sender.push(peer_id, notif).unwrap()
    }

    #[test]
    fn send_n_get_1() {
        let (mut sender, mut receiver) = super::new();
        let peer_id_a = PeerId::random();
        let peer_id_b = PeerId::random();
        let task = async move {
            send_new_peer(&mut sender, peer_id_a);
            send_lost_peer(&mut sender, peer_id_a, DisconnectReason::ConnectionLost);
            send_new_peer(&mut sender, peer_id_a);
            send_lost_peer(&mut sender, peer_id_a, DisconnectReason::Requested);

            // Ensure that only the last message is received.
            let notif = ConnectionNotification::LostPeer(
                ConnectionMetadata::mock(peer_id_a),
                NetworkContext::mock_with_peer_id(peer_id_a),
                DisconnectReason::Requested,
            );
            assert_eq!(receiver.select_next_some().await, notif,);
            // Ensures that there is no other value which is ready
            assert_eq!(receiver.select_next_some().now_or_never(), None);

            send_new_peer(&mut sender, peer_id_a);
            send_new_peer(&mut sender, peer_id_b);

            // Assert that we receive 2 updates, since they are sent for different peers.
            let _ = receiver.select_next_some().await;
            let _ = receiver.select_next_some().await;
            // Ensures that there is no other value which is ready
            assert_eq!(receiver.select_next_some().now_or_never(), None);
        };
        block_on(task);
    }
}
