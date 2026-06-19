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
        Group {
            if projects.isEmpty && conversations.isEmpty {
                coworkWelcomeView
            } else {
                coworkDashboard
            }
        }
    }

    // MARK: - Welcome (sem projetos)

    private var coworkWelcomeView: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 28) {

                // Ícone
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(LinearGradient(
                            colors: [LumeTheme.clay.opacity(0.8), Color.orange.opacity(0.6)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 72, height: 72)
                        .shadow(color: LumeTheme.clay.opacity(0.3), radius: 16, y: 6)
                    Image(systemName: "checklist")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                }

                // Título
                VStack(spacing: 8) {
                    Text("Cowork")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text(String(localized: "Work on your files with the agent — read and write documents,\nrun code in a sandbox, connect tools, and track progress."))
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                // O que você pode fazer
                VStack(spacing: 8) {
                    Text("What you can do here:")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 6) {
                        coworkFeatureRow(
                            icon: "folder.fill",
                            color: LumeTheme.clay,
                            text: String(localized: "Create projects with persistent files and instructions")
                        )
                        coworkFeatureRow(
                            icon: "bubble.left.and.text.bubble.right",
                            color: .accentColor,
                            text: String(localized: "Organize conversations around a single goal")
                        )
                        coworkFeatureRow(
                            icon: "checkmark.circle",
                            color: .green,
                            text: String(localized: "Track tasks and progress in real time")
                        )
                        coworkFeatureRow(
                            icon: "calendar.badge.clock",
                            color: .orange,
                            text: String(localized: "Schedule recurring tasks for the agent to run")
                        )
                        coworkFeatureRow(
                            icon: "doc.text.fill",
                            color: .purple,
                            text: String(localized: "Keep context across sessions with project documents")
                        )
                    }
                    .padding(14)
                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
                }
                .frame(maxWidth: 420)

                // CTAs
                HStack(spacing: 10) {
                    Button(action: onNewProject) {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Create project")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20).padding(.vertical, 11)
                        .background(LumeTheme.clay, in: Capsule())
                        .shadow(color: LumeTheme.clay.opacity(0.3), radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)

                    Button(action: onNewConversation) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.bubble")
                                .font(.system(size: 14, weight: .semibold))
                            Text("New conversation")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(LumeTheme.clay)
                        .padding(.horizontal, 20).padding(.vertical, 11)
                        .background(LumeTheme.clay.opacity(0.10), in: Capsule())
                        .overlay(Capsule().strokeBorder(LumeTheme.clay.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 480)
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
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(color)
            }
            Text(text)
                .font(.system(size: 12))
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
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text("Projects, tasks, and progress")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: onNewConversation) {
                        Label("New task", systemImage: "plus")
                            .font(.system(size: 12, weight: .medium))
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
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                        ForEach(projects) { project in
                            ProjectCard(project: project, onTap: { onSelectProject(project) })
                        }
                        Button(action: onNewProject) {
                            VStack(spacing: 8) {
                                Image(systemName: "plus").font(.system(size: 20)).foregroundStyle(.tertiary)
                                Text("New Project").font(.system(size: 12)).foregroundStyle(.tertiary)
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
                        Image(systemName: "folder.badge.plus").font(.system(size: 36)).foregroundStyle(.tertiary)
                            .symbolRenderingMode(.hierarchical)
                        Text("No projects yet").font(.system(size: 14, weight: .medium))
                        Text("Create a project to organize conversations and keep persistent context.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
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
                                    .font(.system(size: 12)).foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title).font(.system(size: 13)).lineLimit(1)
                                    Text(task.scheduledAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(task.recurrence).font(.system(size: 10)).foregroundStyle(.tertiary)
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
                                    Text(conv.title).font(.system(size: 13)).lineLimit(1).foregroundStyle(.primary)
                                    Spacer()
                                    Text(conv.updatedAt.formatted(.relative(presentation: .named)))
                                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                                    Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.tertiary)
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
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(color)
                Spacer()
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(value).font(.system(size: 22, weight: .bold, design: .rounded))
                    Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
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
                .font(.system(size: 14, weight: .semibold))
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
                        .font(.system(size: 18))
                        .foregroundStyle(LumeTheme.clay)
                    Spacer()
                    Text("\(project.conversations.count)")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(project.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(project.updatedAt.formatted(.relative(presentation: .named)))
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
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
