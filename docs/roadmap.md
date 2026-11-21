# LevelUp — Product & Technical Roadmap

**Competition:** Jetisu Digital Pizza Pitch — SportTech  
**Official Submission Deadline:** November 23, 2026, 09:00  
**Pitch Day:** November 25, 2026, 15:00 (3-minute presentation)  
**Source of Truth:** [README.md](../README.md)

---

## 1. Competition Timeline & Milestones

```mermaid
timeline
    title LevelUp Competition Sprint
    section Sprint to Submission
        20 Nov 2026 : Architecture locked (Blocker v3) : PRD & Wireframes agreed
        21 Nov 2026 : Modular folder structure : 5-tab UI integration : Core contracts preserved
        22 Nov 2026, 20:00 : Internal Submission Deadline : Presentation deck finalized : Backup video recorded
        23 Nov 2026, 09:00 : Official Submission Deadline : Slides locked via Google Form
    section Demo Polish & Pitch
        23-24 Nov 2026 : Critical bug fixes : Pixel & Samsung testing : Demo freeze at 14:00 (24 Nov)
        25 Nov 2026, 15:00 : Pizza Pitch : 3-minute live presentation & hardware demo
```

---

## 2. Competition MVP Scope Matrix

| Priority | Feature Module | Target Delivery | Scope & Criteria |
|---|---|---|---|
| **P0** | App Restriction (Blocker v3) | Nov 20 (Verified) | Opt-in barrier on Pixel 7 Pro; no flashing; media audio paused via `HOME`. |
| **P0** | Camera Squat Detection | Nov 20 (Verified) | Google ML Kit on front camera; 5 reps counted via biomechanical knee angle. |
| **P0** | Temporary Access Grant | Nov 20 (Verified) | 5 calendar minutes unlocked; target app launches cleanly upon completion. |
| **P0** | User Control & Safe Exit | Nov 20 (Verified) | Emergency pause, skip, and voluntary disable available at all times. |
| **P1** | 5-Tab Navigation Structure | Nov 21 | Clean scaffold with Home, Focus, Challenge, Progress, Settings tabs. |
| **P1** | Minimal Dark SportTech Theme | Nov 21 | High-contrast palette (`#101418`, `#1C2429`, `#C7FA5B`). |
| **P1** | Focus Tab App Selection | Nov 21 | Real-time target selection (`YouTube`, `Instagram`, `TikTok`) and status. |
| **P1** | Progress Tab Persistence | Nov 21–22 | Local storage for completed workout sessions; zero fake metrics. |
| **P2** | XP & Level Progression | Nov 23 (Buffer) | Optional gamification layer; only if core unlock loop is 100% bug-free. |
| **P2** | Single Character Concept | Nov 23 (Buffer) | Minimal visual mascot progression tied to verified streaks. |

> [!IMPORTANT]
> **P0/P1 Stability Rule:** If new UI or animations introduce any instability into the core loop (Blocker $\rightarrow$ Squats $\rightarrow$ Unlock), roll back to the stable baseline immediately.

---

## 3. Post-Competition Horizon

### Phase 1 — Stable Core (Weeks 1–2 Post-Competition)
- Multi-app selection and customizable focus schedules (e.g. work hours vs. evening).
- Robust service recovery across device reboots and OS process kills.
- Multi-angle posture detection calibration (side-view vs. diagonal).
- Trilingual localization: Kazakh (`KZ`), Russian (`RU`), English (`EN`).
- Closed user pilot with 30–50 participants to analyze retention and friction.

### Phase 2 — Gamification & Fitness Expansion (Weeks 3–4)
- XP progression mechanics and level thresholds:
  - Transition level $L \rightarrow L+1$: $100 \times L\text{ XP}$
  - Cumulative threshold for level $L$: $50 \times (L - 1) \times L\text{ XP}$
- Anti-farming engine: strict prevention of repeat rewards for the same workout timestamp.
- Introduction of additional verified bodyweight movements (e.g. push-ups, lunges).

### Phase 3 — Adaptive Habit Formation & Health Connect (Weeks 5–6)
- Daily screen time reduction goals and baseline comparison.
- Adaptive challenge scaling based on user fatigue and daily physical limits.
- Non-camera alternatives for public transit, office, or recovery days.
- Integration with Google **Health Connect** (step count and active calorie intake).

### Phase 4 — Cloud Backend, Auth & AI Coach (Weeks 7–10)
- **Supabase** backend infrastructure (PostgreSQL, row-level security, Auth, Realtime).
- Cloud sync of workout telemetry and focus history.
- AI Coach: Weekly habit summaries generated server-side via LLM. Zero raw video buffers ever uploaded to the cloud.

### Phase 5 — Social & Asynchronous Challenges
- Friend codes, cooperative group streaks, and asynchronous physical duels.

### Phase 6 — Multiplayer Real-Time Arena
- Low-latency private challenge rooms with server-side countdown and anti-cheat validation.

### Phase 7 — Commercialization & Google Play Store Compliance
- Google Play Store Accessibility API declaration and compliance review.
- Comprehensive privacy policy, GDPR compliance, and user data deletion mechanisms.
- Implementation of Google Play Billing:
  - Freemium model hypothesis: 1 490 ₸/month for advanced customization and analytics.
  - Essential digital well-being features and voluntary disable remain strictly free.
