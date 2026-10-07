import Foundation
import Testing
@testable import Goose

struct TagRulesTests {
    let work = UUID()
    let home = UUID()

    private func tag(_ code: String, dedicatedTo profileID: UUID? = nil) -> GooseTag {
        var tag = GooseTag(name: code, assignedProfileID: profileID)
        tag.code = code
        return tag
    }

    private func isValid(_ code: String, on profileID: UUID, _ tags: [GooseTag]) -> Bool {
        TagRules.isValidScan(code: code, profileID: profileID, tags: tags)
    }

    @Test func noTagsRegisteredRejectsEverything() {
        #expect(!isValid("GOOSE-ANYTHING", on: work, []))
    }

    @Test func unknownCodeIsRejected() {
        let tags = [tag("GOOSE-A")]
        #expect(!isValid("GOOSE-NOT-MINE", on: work, tags))
    }

    @Test func generalTagWorksOnProfileWithoutDedicatedTag() {
        let tags = [tag("GOOSE-A")]
        #expect(isValid("GOOSE-A", on: work, tags))
    }

    @Test func anotherProfilesDedicatedTagWorksOnProfileWithoutOne() {
        let tags = [tag("GOOSE-HOME", dedicatedTo: home)]
        #expect(isValid("GOOSE-HOME", on: work, tags))
    }

    @Test func dedicatedTagWorksOnItsOwnProfile() {
        let tags = [tag("GOOSE-A"), tag("GOOSE-WORK", dedicatedTo: work)]
        #expect(isValid("GOOSE-WORK", on: work, tags))
    }

    @Test func generalTagIsRejectedOnProfileWithDedicatedTag() {
        let tags = [tag("GOOSE-A"), tag("GOOSE-WORK", dedicatedTo: work)]
        #expect(!isValid("GOOSE-A", on: work, tags))
    }

    @Test func anotherProfilesDedicatedTagIsRejectedOnProfileWithOne() {
        let tags = [tag("GOOSE-WORK", dedicatedTo: work), tag("GOOSE-HOME", dedicatedTo: home)]
        #expect(!isValid("GOOSE-HOME", on: work, tags))
    }

    @Test func everyDedicatedTagOfAProfileWorks() {
        let tags = [tag("GOOSE-WORK-1", dedicatedTo: work), tag("GOOSE-WORK-2", dedicatedTo: work)]
        #expect(isValid("GOOSE-WORK-1", on: work, tags))
        #expect(isValid("GOOSE-WORK-2", on: work, tags))
    }

    @Test func newTagsGetUniqueCodes() {
        let codes = Set((0..<100).map { _ in GooseTag(name: "t").code })
        #expect(codes.count == 100)
    }
}
