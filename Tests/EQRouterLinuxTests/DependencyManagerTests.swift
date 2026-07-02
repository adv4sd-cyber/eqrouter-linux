import Testing
@testable import EQRouterLinux

@Suite struct DependencyManagerTests {
    typealias DM = DependencyManager

    @Test func aptPlanRefreshesThenInstallsWithSudo() {
        let plan = DM.buildPlan(packageManager: .apt, elevation: .sudo, assumeYes: true)
        #expect(plan.packages == ["pulseaudio-utils"])
        #expect(plan.commands == [
            ["sudo", "apt-get", "update"],
            ["sudo", "apt-get", "install", "-y", "pulseaudio-utils"],
        ])
        #expect(plan.shellString ==
            "sudo apt-get update && sudo apt-get install -y pulseaudio-utils")
    }

    @Test func rootNeedsNoElevationPrefix() {
        let plan = DM.buildPlan(packageManager: .dnf, elevation: .none, assumeYes: true)
        #expect(plan.commands == [["dnf", "install", "-y", "pulseaudio-utils"]])
    }

    @Test func pkexecPrefixApplied() {
        let plan = DM.buildPlan(packageManager: .zypper, elevation: .pkexec, assumeYes: true)
        #expect(plan.commands == [["pkexec", "zypper", "--non-interactive", "install", "pulseaudio-utils"]])
    }

    @Test func archUsesLibpulsePackage() {
        let plan = DM.buildPlan(packageManager: .pacman, elevation: .sudo, assumeYes: true)
        #expect(plan.packages == ["libpulse"])
        #expect(plan.commands == [["sudo", "pacman", "-S", "--needed", "--noconfirm", "libpulse"]])
    }

    @Test func gentooUsesPulseaudioAtom() {
        let plan = DM.buildPlan(packageManager: .emerge, elevation: .sudo, assumeYes: true)
        #expect(plan.packages == ["media-sound/pulseaudio"])
    }

    @Test func assumeYesTogglesConfirmationFlags() {
        let interactive = DM.buildPlan(packageManager: .apt, elevation: .sudo, assumeYes: false)
        #expect(interactive.commands.last == ["sudo", "apt-get", "install", "pulseaudio-utils"])
    }

    @Test func onlyRootAndPkexecElevateWithoutATerminal() {
        // sudo needs a TTY password, so it must not be attempted over HTTP.
        #expect(DM.Elevation.none.canElevateNonInteractively == true)
        #expect(DM.Elevation.pkexec.canElevateNonInteractively == true)
        #expect(DM.Elevation.sudo.canElevateNonInteractively == false)
        #expect(DM.Elevation.unavailable.canElevateNonInteractively == false)
    }

    @Test func everyPackageManagerHasProbeAndPackages() {
        for pm in DM.PackageManager.allCases {
            #expect(!pm.probeBinary.isEmpty)
            #expect(!pm.pulsePackages.isEmpty)
            #expect(!pm.installCommands(packages: pm.pulsePackages, assumeYes: true).isEmpty)
        }
    }
}
