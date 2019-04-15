
namespace Generator.Api.Controllers
{
    using System;
    using System.Collections.Generic;
    using System.Linq;
    using Faker;
    using Faker.Extensions;
    using Microsoft.AspNetCore.Mvc;

    [Route("[action]")]
    public class GeneratorController:Controller
    {
        [HttpGet]
        public IEnumerable<string> Names(Range range)
            => range.Of(Name.FullName);

        [HttpGet]
        public IEnumerable<string> PhoneNumbers(Range range)
            => range.Of(Phone.Number);

        [HttpGet]
        public IEnumerable<int> Numbers(Range range)
            => range.Of(RandomNumber.Next);

        [HttpGet]
        public IEnumerable<string> Companies(Range range)
            => range.Of(Company.Name);

        [HttpGet]
        public IEnumerable<string> Paragraphs(Range range)
            => range.Of(() => Lorem.Paragraph(3));

        [HttpGet]
        public IEnumerable<string> CatchPhrases(Range range)
            => range.Of(Company.CatchPhrase);

        [HttpGet]
        public IEnumerable<string> Marketing(Range range)
            => range.Of(Company.BS);

        [HttpGet]
        public IEnumerable<string> Emails(Range range)
            => range.Of(Internet.Email);

        [HttpGet]
        public IEnumerable<string> Domains(Range range)
            => range.Of(Internet.DomainName);
    }

    public class Range
    {
        public int Count { get; set; } = 10;
        public bool Sort { get; set; } = false;

        public IEnumerable<TItem> Of<TItem>(Func<TItem> generateItem)
            => Count.Times(i => generateItem())
                .OrderBy(n => Sort ? n : default(TItem));
    }
}
