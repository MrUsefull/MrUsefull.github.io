+++
title = 'Resume as code'
date = 2025-08-19
draft = false
toc = true
tags = ["ci", "resume", "projects"]
summary = "Treating my resume with the same respect I give my code."
+++

This post is about finally moving my resume to version control. Having my resume managed the same way
that everything else I work on is handled reduces mental overhead.

## Alternatives Considered

### Google Docs

Google Docs was actually how I previously handled things. It works, but I find that I miss VCS and tooling that I'm more familiar with.

### Word

Not really a reasonable solution for me.

### LaTeX

Actually quite a good solution. I'm just more familiar with Markdown, since that's what I use almost daily.

## The Implementation

1. Have a Markdown document. Generic small sample below.

    ```Markdown
    # First Last
    
    ## Job Title
    
    XXX-XXX-XXXX | blog.url.here | [an@email.fqdn](mailto:an@email.fqdn)
    
    ### Job Title, Company Name | StartDate - EndDate
    
    * Did stuff, big measured impact
    * Did great things, huge even.
    * Massive metrics 10000% improvements
    ```

2. Convert to PDF format. I chose to use [md2pdf](https://github.com/jmaupetit/md2pdf).
    I considered other options such as pandoc, but I had better luck with md2pdf.

    ```bash
    md2pdf resume.md "First_Last_Resume_${DATE}.pdf"
    md2pdf resume.md "First_Last_Resume_latest.pdf" 
    ```

    Results

    [![Pdf Output](/images/2025-08-19-resume-as-code/output.png)](/images/2025-08-19-resume-as-code/output.png)

3. Generate an easily accessible link from the repository README.md.

    ```Markdown
    - [Latest Resume PDF](https://gitlab.fqdn/username/resume/-/jobs/artifacts/master/raw/First_Last_Resume_latest.pdf?job=build_resume)
    ```

4. Do it in CI. My current `.gitlab-ci.yml` on my self-hosted GitLab instance.

    ```yaml
    stages:
      - build
    
    build_resume:
      stage: build
      image: python:3.11
      before_script:
        - pip install md2pdf
      script:
        - DATE=$(date +%Y%m%d)
        - md2pdf resume.md "First_Last_Resume_${DATE}.pdf"
        - md2pdf resume.md "First_Last_Resume_latest.pdf"
      artifacts:
        paths:
          - "First_Last_Resume_*.pdf"
        expire_in: 1 year
      rules:
        - if: $CI_COMMIT_BRANCH == "master"
        - if: $CI_COMMIT_TAG
    ```

## Conclusion

This approach positions me to have CI jobs check spelling, lint my resume's Markdown, or implement any other improvements I think of later.
