"""Tests for markdown resume parser."""

from jpresume.parser import parse_resume


def test_parse_name(sample_resume_text):
    resume = parse_resume(sample_resume_text)
    assert resume.name == "Jane Doe"


def test_parse_contact(sample_resume_text):
    resume = parse_resume(sample_resume_text)
    assert resume.contact.email == "jane@example.com"
    assert resume.contact.phone == "+81-80-9999-0000"


def test_parse_summary(sample_resume_text):
    resume = parse_resume(sample_resume_text)
    assert "Full-stack developer" in resume.summary


def test_parse_experience(sample_resume_text):
    resume = parse_resume(sample_resume_text)
    assert len(resume.experience) == 2
    assert resume.experience[0].company == "Google"
    assert resume.experience[0].title == "Software Engineer"
    assert resume.experience[0].start_date == "Apr 2020"
    assert resume.experience[0].end_date == "Present"
    assert len(resume.experience[0].bullets) == 2

    assert resume.experience[1].company == "Startup Co"
    assert resume.experience[1].title == "Junior Developer"


def test_parse_education(sample_resume_text):
    resume = parse_resume(sample_resume_text)
    assert len(resume.education) == 2
    assert resume.education[0].institution == "MIT"
    assert resume.education[0].degree == "M.S. Computer Science"
    assert resume.education[1].institution == "Tokyo University"


def test_parse_skills(sample_resume_text):
    resume = parse_resume(sample_resume_text)
    assert "Python" in resume.skills
    assert "Go" in resume.skills
    assert "Docker" in resume.skills
    assert len(resume.skills) == 7


def test_parse_certifications(sample_resume_text):
    resume = parse_resume(sample_resume_text)
    assert len(resume.certifications) == 1
    assert "AWS" in resume.certifications[0]


def test_parse_languages(sample_resume_text):
    resume = parse_resume(sample_resume_text)
    assert len(resume.languages) == 2
    assert any("English" in l for l in resume.languages)
    assert any("Japanese" in l for l in resume.languages)


def test_parse_empty_resume():
    resume = parse_resume("")
    assert resume.name is None
    assert len(resume.experience) == 0


def test_parse_minimal_resume():
    text = "# John\n\n## Experience\n\n### Acme | Dev | 2020 - 2021\n\n- Did things\n"
    resume = parse_resume(text)
    assert resume.name == "John"
    assert len(resume.experience) == 1
    assert resume.experience[0].company == "Acme"
