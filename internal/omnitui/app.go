package omnitui

import (
	"fmt"
	"os/exec"
	"strings"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
)

type Action struct {
	Title       string
	Target      string
	Description string
}

type Model struct {
	actions []Action
	cursor  int
	running string
	last    string
	width   int
}

type finishedMsg struct {
	target string
	err    error
}

func DefaultActions() []Action {
	return []Action{
		{Title: "Start provider", Target: "provider", Description: "Register/start Omni libvirt provider"},
		{Title: "Provider status", Target: "provider-status", Description: "Show local provider container status"},
		{Title: "Apply machine classes", Target: "mc", Description: "Apply UI-selectable Omni MachineClasses"},
		{Title: "Sync cluster", Target: "cluster", Description: "Validate/sync Omni cluster template"},
		{Title: "Cluster status", Target: "status", Description: "Show Omni cluster template status"},
		{Title: "Provision lab", Target: "lab", Description: "Run provider, machine classes, and cluster sync"},
		{Title: "Provider logs", Target: "provider-logs", Description: "Tail provider logs"},
		{Title: "Stop provider", Target: "provider-down", Description: "Stop local provider container"},
		{Title: "Deploy Omni VM", Target: "deploy-remote", Description: "Sync/apply Omni service VM deployment"},
	}
}

func NewModel(actions []Action) Model {
	return Model{actions: actions}
}

func (m Model) CurrentAction() Action {
	if len(m.actions) == 0 {
		return Action{}
	}
	return m.actions[m.cursor]
}

func (m *Model) MoveUp() {
	if len(m.actions) == 0 {
		return
	}
	m.cursor--
	if m.cursor < 0 {
		m.cursor = len(m.actions) - 1
	}
}

func (m *Model) MoveDown() {
	if len(m.actions) == 0 {
		return
	}
	m.cursor = (m.cursor + 1) % len(m.actions)
}

func (m Model) CommandForCurrentAction() *exec.Cmd {
	action := m.CurrentAction()
	return exec.Command("make", action.Target)
}

func (m Model) Init() tea.Cmd {
	return nil
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		return m, nil
	case tea.KeyPressMsg:
		switch msg.String() {
		case "ctrl+c", "q", "esc":
			return m, tea.Quit
		case "up", "k":
			m.MoveUp()
			return m, nil
		case "down", "j":
			m.MoveDown()
			return m, nil
		case "enter":
			action := m.CurrentAction()
			if action.Target == "" {
				return m, nil
			}
			m.running = action.Target
			cmd := m.CommandForCurrentAction()
			return m, tea.ExecProcess(cmd, func(err error) tea.Msg {
				return finishedMsg{target: action.Target, err: err}
			})
		}
	case finishedMsg:
		m.running = ""
		if msg.err != nil {
			m.last = fmt.Sprintf("make %s failed: %v", msg.target, msg.err)
		} else {
			m.last = fmt.Sprintf("make %s finished", msg.target)
		}
		return m, nil
	}
	return m, nil
}

func (m Model) View() tea.View {
	v := tea.NewView(m.render())
	v.WindowTitle = "omni-on-unraid"
	return v
}

func (m Model) render() string {
	width := m.width
	if width < 72 {
		width = 72
	}

	titleStyle := lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("86"))
	itemStyle := lipgloss.NewStyle().
		PaddingLeft(2)
	selectedStyle := lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("212")).
		PaddingLeft(1)
	mutedStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("244"))
	statusStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("220"))
	boxStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("62")).
		Padding(1, 2).
		Width(min(width-4, 92))

	var b strings.Builder
	b.WriteString(titleStyle.Render("omni-on-unraid"))
	b.WriteString("\n")
	b.WriteString(mutedStyle.Render("Use j/k or arrows, enter to run, q to quit. Commands are make targets."))
	b.WriteString("\n\n")

	for i, action := range m.actions {
		cursor := " "
		style := itemStyle
		if i == m.cursor {
			cursor = ">"
			style = selectedStyle
		}
		line := fmt.Sprintf("%s %-18s %s", cursor, action.Target, action.Description)
		b.WriteString(style.Render(line))
		b.WriteString("\n")
	}

	if m.running != "" {
		b.WriteString("\n")
		b.WriteString(statusStyle.Render("running: make " + m.running))
	} else if m.last != "" {
		b.WriteString("\n")
		b.WriteString(statusStyle.Render(m.last))
	}

	return boxStyle.Render(b.String())
}
