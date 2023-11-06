package runner

import (
	"fmt"

	"github.com/lukemarsden/helix/api/pkg/types"
)

func getLastInteractionID(session *types.Session) (string, error) {
	if len(session.Interactions) == 0 {
		return "", fmt.Errorf("session has no messages")
	}
	interaction := session.Interactions[len(session.Interactions)-1]
	if interaction.Creator != types.CreatorTypeSystem {
		return "", fmt.Errorf("session does not have a system interaction as last message")
	}
	return interaction.ID, nil
}