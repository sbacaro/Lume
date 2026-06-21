//
//  CoworkDashboardView.swift
//  Lume
//
//  Created by Samuel Bacaro on 09/06/26.
//

import SwiftUI
import SwiftData

struct CoworkDashboardView: View {
    let projects: [Project]
    let conversations: [Conversation]
    let onSelectProject: (Project) -> Void
    let onSelectConversation: (Conversation) -> Void
    let onNewProject: () -> Void
    let onNewConversation: () -> Void

    @Query(sort: \ScheduledTask.scheduledAt) private var tasks: [ScheduledTask]

    var body: some View {
        coworkWelcomeView
            .overlay(alignment: .bottomTrailing) { VersionBadge() }
    }

    // MARK: - Welcome (sem projetos)

    private var coworkWelcomeView: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 22) {
                ModeWelcomeHeader(
                    icon: "square.grid.2x2.fill",
                    accent: LumeTheme.clay,
                    title: "Cowork",
                    subtitle: "Automate work over the files in a folder."
                )
                HStack(spacing: 10) {
                    ModePrimaryButton(icon: "folder.badge.plus", label: "Create a project",
                                      accent: LumeTheme.clay, action: onNewProject)
                    ModeSecondaryButton(label: "New conversation", accent: LumeTheme.clay, action: onNewConversation)
                }
                Text("A project connects a folder Lume can read, write, and organize.")
                    .font(.lume(.subheadline)).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center).frame(maxWidth: 360)
                CapabilityGrid(items: [
                    (icon: "doc.on.doc", text: "Read & write your files"),
                    (icon: "terminal", text: "Run code in a sandbox"),
                    (icon: "puzzlepiece.extension", text: "Connect MCP tools"),
                    (icon: "checklist", text: "Track tasks & progress"),
                ], accent: LumeTheme.clay)
                .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }

    private func coworkFeatureRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 26, height: 26)
                Image(systemName: icon)
                    .font(.lume(.footnote, weight: .medium))
                    .foregroundStyle(color)
            }
            Text(text)
                .font(.lume(.subheadline))
                .foregroundStyle(.primary)
            Spacer()
        }
    }

    // MARK: - Dashboard (com projetos/conversas)

    private var coworkDashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cowork")
                            .font(.lume(.title1, weight: .bold, design: .rounded))
                        Text("Projects, tasks, and progress")
                            .font(.lume(.callout)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: onNewConversation) {
                        Label("New task", systemImage: "plus")
                            .font(.lume(.subheadline, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                }

                // Stats row
                HStack(spacing: 12) {
                    statCard(value: "\(projects.count)", label: "Projects", icon: "folder.fill", color: LumeTheme.clay)
                    statCard(value: "\(conversations.count)", label: String(localized: "Conversations"), icon: "bubble.left.fill", color: .accentColor)
                    statCard(value: "\(tasks.filter { !$0.isCompleted }.count)", label: String(localized: "Pending"), icon: "clock.fill", color: .orange)
                    statCard(value: "\(conversations.flatMap { $0.messages }.count)", label: String(localized: "Messages"), icon: "text.bubble.fill", color: .purple)
                }

                // Projetos
                if !projects.isEmpty {
                    dashSection("Projects", icon: "folder") {
                        Button(action: onNewProject) {
                            Label("New Project", systemImage: "plus")
                                .font(.lume(.footnote)).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                        ForEach(projects) { project in
                            ProjectCard(project: project, onTap: { onSelectProject(project) })
                        }
                        Button(action: onNewProject) {
                            VStack(spacing: 8) {
                                Image(systemName: "plus").font(.lume(.title2)).foregroundStyle(.tertiary)
                                Text("New Project").font(.lume(.subheadline)).foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 90)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus").font(.lume(.largeTitle)).foregroundStyle(.tertiary)
                            .symbolRenderingMode(.hierarchical)
                        Text("No projects yet").font(.lume(.body, weight: .medium))
                        Text("Create a project to organize conversations and keep persistent context.")
                            .font(.lume(.subheadline)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Create first project", action: onNewProject).buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(32)
                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // Tarefas agendadas
                if !tasks.isEmpty {
                    dashSection(String(localized: "Scheduled Tasks"), icon: "calendar.badge.clock") { EmptyView() }

                    VStack(spacing: 6) {
                        ForEach(tasks.filter { !$0.isCompleted }.prefix(5)) { task in
                            HStack(spacing: 12) {
                                Image(systemName: "clock")
                                    .font(.lume(.subheadline)).foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title).font(.lume(.callout)).lineLimit(1)
                                    Text(task.scheduledAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.lume(.footnote)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(task.recurrence).font(.lume(.caption)).foregroundStyle(.tertiary)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.primary.opacity(0.06), in: Capsule())
                            }
                            .padding(10)
                            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }

                // Atividade recente
                if !conversations.isEmpty {
                    dashSection(String(localized: "Recent Activity"), icon: "clock.arrow.circlepath") { EmptyView() }

                    VStack(spacing: 4) {
                        ForEach(conversations.prefix(8)) { conv in
                            Button { onSelectConversation(conv) } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(conv.messages.isEmpty ? Color.primary.opacity(0.1) : Color.accentColor.opacity(0.3))
                                        .frame(width: 8, height: 8)
                                    Text(conv.title).font(.lume(.callout)).lineLimit(1).foregroundStyle(.primary)
                                    Spacer()
                                    Text(conv.updatedAt.formatted(.relative(presentation: .named)))
                                        .font(.lume(.caption)).foregroundStyle(.tertiary)
                                    Image(systemName: "chevron.right").font(.lume(.caption)).foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Helpers

    private func statCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: icon).font(.lume(.subheadline)).foregroundStyle(color)
                Spacer()
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(value).font(.lume(.title2, weight: .bold, design: .rounded))
                    Text(label).font(.lume(.footnote)).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
    }

    @ViewBuilder
    private func dashSection<Action: View>(_ title: String, icon: String, @ViewBuilder action: () -> Action) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.lume(.body, weight: .semibold))
            Spacer()
            action()
        }
    }
}

// MARK: - Project Card

struct ProjectCard: View {
    let project: Project
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: project.icon)
                        .font(.lume(.title2))
                        .foregroundStyle(LumeTheme.clay)
                    Spacer()
                    Text("\(project.conversations.count)")
                        .font(.lume(.caption, weight: .medium)).foregroundStyle(.tertiary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(project.name).font(.lume(.callout, weight: .semibold)).lineLimit(1)
                    Text(project.updatedAt.formatted(.relative(presentation: .named)))
                        .font(.lume(.caption)).foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
